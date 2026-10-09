import LidAwakeCore
import Foundation
import os

final class HelperService: NSObject, NSXPCListenerDelegate, LidAwakeHelperXPCProtocol {
    private let pmsetService = PMSetService()
    private let clientAuthorizer = HelperClientAuthorizer()
    // A rejection here is the only signal the app gets, and it reaches the app as
    // a bare connection interruption with no reason attached. NSLog from a daemon
    // is redacted to `<private>` in the unified log, which makes these rejections
    // impossible to diagnose from a user's machine, so log them explicitly public.
    private let logger = Logger(subsystem: LidAwakeHelperConstants.machServiceName, category: "listener")
    private let codeSigningRequirement: String? = {
        let info = try? SecurityCodeSigningInfoProvider().currentProcessCodeSigningInfo()
        return HelperCodeSigningRequirement.requirement(teamIdentifier: info?.teamIdentifier)
    }()
    /// Every connection gets its own queue, so without this two requests could
    /// run `pmset` at once and finish in either order. The watchdog relies on it
    /// too: it is only touched from here.
    private let commandQueue = DispatchQueue(label: "\(LidAwakeHelperConstants.machServiceName).commands")
    private lazy var restoreWatchdog = ClosedLidRestoreWatchdog(
        restore: { [pmsetService, logger] in
            do {
                try pmsetService.setClosedLidMode(enabled: false)
                logger.notice("Restored closed-lid mode after the client exited without restoring it")
                return true
            } catch {
                logger.error("Could not restore closed-lid mode after the client exited, will retry: \(error.localizedDescription, privacy: .public)")
                return false
            }
        },
        readClosedLidStatus: { [pmsetService] in
            pmsetService.readClosedLidStatus()
        },
        watchProcessExit: { [commandQueue] processID, handler in
            DispatchProcessExitWatch(processID: processID, queue: commandQueue, handler: handler)
        },
        scheduleRetry: { [commandQueue] delay, work in
            commandQueue.asyncAfter(deadline: .now() + delay, execute: work)
        }
    )

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let processID = connection.processIdentifier
        guard clientAuthorizer.isAuthorized(processID: processID) else {
            logger.error("Rejected XPC connection: client is not authorized pid=\(processID, privacy: .public)")
            return false
        }

        guard let codeSigningRequirement else {
            logger.error("Rejected XPC connection: this helper build has no Team ID pid=\(processID, privacy: .public)")
            return false
        }

        connection.setCodeSigningRequirement(codeSigningRequirement)
        logger.info("Accepted XPC connection pid=\(processID, privacy: .public) requirement=\(codeSigningRequirement, privacy: .public)")

        connection.exportedInterface = NSXPCInterface(with: LidAwakeHelperXPCProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func readClosedLidStatus(reply: @escaping (String) -> Void) {
        reply(pmsetService.readClosedLidStatus().displayText)
    }

    func setClosedLidMode(enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        // Only valid while this call is being delivered, so read it before
        // hopping queues. It names the client the accept-time checks approved.
        let clientProcessID = NSXPCConnection.current()?.processIdentifier
        commandQueue.async { [self] in
            var changeError: Error?
            do {
                try pmsetService.setClosedLidMode(enabled: enabled)
            } catch {
                changeError = error
            }

            if let clientProcessID {
                restoreWatchdog.closedLidModeChangeAttempted(
                    enabled: enabled,
                    outcome: ClosedLidModeChangeOutcome(error: changeError),
                    clientProcessID: clientProcessID
                )
            }
            reply(changeError == nil, changeError?.localizedDescription)
        }
    }
}

let service = HelperService()
let listener = NSXPCListener(machServiceName: LidAwakeHelperConstants.machServiceName)
listener.delegate = service
listener.resume()
RunLoop.current.run()
