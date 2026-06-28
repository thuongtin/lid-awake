import LidAwakeCore
import Foundation
import ServiceManagement

enum ClosedLidHelperStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unavailable(String)

    var displayText: String {
        switch self {
        case .notRegistered:
            "Not set up"
        case .enabled:
            "Ready"
        case .requiresApproval:
            "Needs approval"
        case .notFound:
            "Helper missing"
        case let .unavailable(message):
            message
        }
    }

    var canControlClosedLidMode: Bool {
        self == .enabled
    }

    var needsPermissionPrompt: Bool {
        switch self {
        case .enabled:
            false
        case .notRegistered, .requiresApproval, .notFound, .unavailable(_):
            true
        }
    }
}

final class ClosedLidHelperService {
    private let xpcResponseTimeout: TimeInterval = 4

    private var service: SMAppService {
        SMAppService.daemon(plistName: LidAwakeHelperConstants.daemonPlistName)
    }

    var status: ClosedLidHelperStatus {
        switch service.status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .unavailable("Unknown helper status")
        }
    }

    func register() throws {
        switch status {
        case .enabled, .requiresApproval:
            return
        case .notRegistered, .notFound, .unavailable(_):
            try service.register()
        }
    }

    func repairRegistration() throws {
        switch status {
        case .notRegistered:
            break
        case .enabled, .requiresApproval, .notFound, .unavailable(_):
            try? service.unregister()
        }

        try service.register()
    }

    func unregister() throws {
        guard status != .notRegistered else {
            return
        }

        try service.unregister()
    }

    func readClosedLidStatus(reply: @escaping (ClosedLidStatus) -> Void) {
        withRemoteObject { remote, finish in
            remote.readClosedLidStatus { value in
                finish {
                    reply(Self.closedLidStatus(from: value))
                }
            }
        } failure: { _ in
            reply(.notReported)
        }
    }

    func setClosedLidMode(enabled: Bool, reply: @escaping (Result<Void, Error>) -> Void) {
        withRemoteObject { remote, finish in
            remote.setClosedLidMode(enabled: enabled) { success, message in
                finish {
                    if success {
                        reply(.success(()))
                    } else {
                        reply(.failure(PMSetError.commandFailed(1, message ?? "Helper command failed.")))
                    }
                }
            }
        } failure: { message in
            reply(.failure(PMSetError.commandFailed(1, message)))
        }
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func withRemoteObject(
        operation: @escaping (LidAwakeHelperXPCProtocol, @escaping (@escaping () -> Void) -> Void) -> Void,
        failure: @escaping (String) -> Void
    ) {
        guard status == .enabled else {
            failure("Closed-lid helper is not available.")
            return
        }

        let completionGate = XPCCompletionGate()
        let connection = NSXPCConnection(
            machServiceName: LidAwakeHelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: LidAwakeHelperXPCProtocol.self)
        connection.invalidationHandler = {
            completionGate.run {
                failure("Closed-lid helper connection was invalidated.")
            }
        }
        connection.interruptionHandler = {
            completionGate.run {
                connection.invalidate()
                failure("Closed-lid helper connection was interrupted.")
            }
        }
        connection.resume()

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            completionGate.run {
                connection.invalidate()
                failure(error.localizedDescription)
            }
        }

        guard let remote = proxy as? LidAwakeHelperXPCProtocol else {
            completionGate.run {
                connection.invalidate()
                failure("Closed-lid helper proxy is not available.")
            }
            return
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + xpcResponseTimeout) {
            completionGate.run {
                connection.invalidate()
                failure("Lid Awake Helper did not respond. Repair the helper, then try again.")
            }
        }

        operation(remote) { completion in
            completionGate.run {
                connection.invalidate()
                completion()
            }
        }
    }

    private static func closedLidStatus(from value: String) -> ClosedLidStatus {
        switch value {
        case ClosedLidStatus.enabled.displayText:
            .enabled
        case ClosedLidStatus.disabled.displayText:
            .disabled
        default:
            .notReported
        }
    }
}

private final class XPCCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didFinish = false

    func run(_ operation: () -> Void) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()
        operation()
    }
}
