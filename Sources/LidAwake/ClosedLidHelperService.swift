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

/// Why a helper call could not complete.
///
/// These have to be told apart because `SMAppService` keeps reporting an
/// approved registration as `.enabled` even when the app can no longer talk to
/// the helper it approved. The registration is pinned to the bundle that
/// created it, so after Lid Awake is updated, moved, or reinstalled the daemon
/// launchd starts can belong to a different copy of the app and will refuse the
/// connection. Re-registering from the running bundle is the only fix, and it
/// is a different action from setting the helper up for the first time.
enum ClosedLidHelperFailure: LocalizedError, Equatable {
    /// `SMAppService` reports the helper cannot be used at all.
    case helperNotReady
    /// macOS accepted the connection and then tore it down, either because the
    /// helper refused this client or because it stopped running.
    case connectionLost
    /// The helper took the connection but never answered.
    case timedOut
    /// The helper ran the command and reported a failure.
    case commandFailed(String)

    static let connectionLostMessage =
        "Lid Awake could not reach Lid Awake Helper. This usually happens after the app is updated, moved, or reinstalled, because the approved helper still belongs to the previous copy. Repair the helper to reconnect."
    /// Same failure, written to fit the two lines the menu bar popover gives it.
    static let connectionLostCompactMessage =
        "Lid Awake cannot reach Lid Awake Helper. Repair it to restore closed-lid playback."
    static let timedOutMessage =
        "Lid Awake Helper did not respond. Repair the helper, then try again."

    var errorDescription: String? {
        switch self {
        case .helperNotReady:
            "Closed-lid helper is not available."
        case .connectionLost:
            Self.connectionLostMessage
        case .timedOut:
            Self.timedOutMessage
        case let .commandFailed(message):
            message
        }
    }

    /// Whether re-registering the helper is the action that can clear this.
    var isRecoverableByRepair: Bool {
        switch self {
        case .connectionLost, .timedOut:
            true
        case .helperNotReady, .commandFailed:
            false
        }
    }
}

final class ClosedLidHelperService {
    private let xpcResponseTimeout: TimeInterval = 4
    /// launchd tears down an idle on-demand daemon between calls, so one lost
    /// connection is retried before the app blames the registration.
    private let connectionLostRetryCount = 1

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

    /// Round-trips the cheapest call the helper vends so the app can tell an
    /// approved-and-working registration apart from an approved-but-unreachable
    /// one. Nothing else reports that difference: `status` only reads the
    /// `SMAppService` record, which stays `.enabled` either way.
    func probeConnection(reply: @escaping (Result<Void, ClosedLidHelperFailure>) -> Void) {
        withRemoteObject { remote, finish in
            remote.readClosedLidStatus { _ in
                finish {
                    reply(.success(()))
                }
            }
        } failure: { failure in
            reply(.failure(failure))
        }
    }

    func setClosedLidMode(enabled: Bool, reply: @escaping (Result<Void, Error>) -> Void) {
        withRemoteObject { remote, finish in
            remote.setClosedLidMode(enabled: enabled) { success, message in
                finish {
                    if success {
                        reply(.success(()))
                    } else {
                        reply(.failure(ClosedLidHelperFailure.commandFailed(message ?? "Helper command failed.")))
                    }
                }
            }
        } failure: { failure in
            reply(.failure(failure))
        }
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func withRemoteObject(
        operation: @escaping (LidAwakeHelperXPCProtocol, @escaping (@escaping () -> Void) -> Void) -> Void,
        failure: @escaping (ClosedLidHelperFailure) -> Void
    ) {
        connect(
            operation: operation,
            retriesRemaining: connectionLostRetryCount,
            // One deadline for the whole call, retry included, so callers get an
            // answer inside `xpcResponseTimeout` no matter how often it retries.
            deadline: .now() + xpcResponseTimeout,
            failure: failure
        )
    }

    private func connect(
        operation: @escaping (LidAwakeHelperXPCProtocol, @escaping (@escaping () -> Void) -> Void) -> Void,
        retriesRemaining: Int,
        deadline: DispatchTime,
        failure: @escaping (ClosedLidHelperFailure) -> Void
    ) {
        guard status == .enabled else {
            failure(.helperNotReady)
            return
        }

        let fail: (ClosedLidHelperFailure) -> Void = { [self] reason in
            guard reason == .connectionLost, retriesRemaining > 0, deadline > .now() else {
                failure(reason)
                return
            }

            connect(
                operation: operation,
                retriesRemaining: retriesRemaining - 1,
                deadline: deadline,
                failure: failure
            )
        }

        let completionGate = XPCCompletionGate()
        let connection = NSXPCConnection(
            machServiceName: LidAwakeHelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: LidAwakeHelperXPCProtocol.self)
        // All three of these mean the same thing to the app: macOS had a
        // connection and then took it away. The helper refusing this client in
        // `shouldAcceptNewConnection` lands here too, as an interruption.
        connection.invalidationHandler = {
            completionGate.run {
                fail(.connectionLost)
            }
        }
        connection.interruptionHandler = {
            completionGate.run {
                connection.invalidate()
                fail(.connectionLost)
            }
        }
        connection.resume()

        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            completionGate.run {
                connection.invalidate()
                fail(.connectionLost)
            }
        }

        guard let remote = proxy as? LidAwakeHelperXPCProtocol else {
            completionGate.run {
                connection.invalidate()
                fail(.commandFailed("Closed-lid helper proxy is not available."))
            }
            return
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline) {
            completionGate.run {
                connection.invalidate()
                fail(.timedOut)
            }
        }

        operation(remote) { completion in
            completionGate.run {
                connection.invalidate()
                completion()
            }
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
