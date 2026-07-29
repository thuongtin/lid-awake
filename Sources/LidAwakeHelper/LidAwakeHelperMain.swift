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
        do {
            try pmsetService.setClosedLidMode(enabled: enabled)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }
}

let service = HelperService()
let listener = NSXPCListener(machServiceName: LidAwakeHelperConstants.machServiceName)
listener.delegate = service
listener.resume()
RunLoop.current.run()
