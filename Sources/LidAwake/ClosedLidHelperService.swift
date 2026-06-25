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

    func unregister() throws {
        guard status != .notRegistered else {
            return
        }

        try service.unregister()
    }

    func readClosedLidStatus(reply: @escaping (ClosedLidStatus) -> Void) {
        withRemoteObject { remote, finish in
            remote.readClosedLidStatus { value in
                reply(Self.closedLidStatus(from: value))
                finish()
            }
        } failure: {
            reply(.notReported)
        }
    }

    func setClosedLidMode(enabled: Bool, reply: @escaping (Result<Void, Error>) -> Void) {
        withRemoteObject { remote, finish in
            remote.setClosedLidMode(enabled: enabled) { success, message in
                if success {
                    reply(.success(()))
                } else {
                    reply(.failure(PMSetError.commandFailed(1, message ?? "Helper command failed.")))
                }
                finish()
            }
        } failure: {
            reply(.failure(PMSetError.commandFailed(1, "Closed-lid helper is not available.")))
        }
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func withRemoteObject(
        operation: @escaping (LidAwakeHelperXPCProtocol, @escaping () -> Void) -> Void,
        failure: @escaping () -> Void
    ) {
        guard status == .enabled else {
            failure()
            return
        }

        let connection = NSXPCConnection(
            machServiceName: LidAwakeHelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: LidAwakeHelperXPCProtocol.self)
        connection.resume()

        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            connection.invalidate()
            failure()
        }

        guard let remote = proxy as? LidAwakeHelperXPCProtocol else {
            connection.invalidate()
            failure()
            return
        }

        operation(remote) {
            connection.invalidate()
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
