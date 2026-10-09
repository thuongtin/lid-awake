import Foundation

public protocol ProcessExitWatching: AnyObject {
    func cancel()
}

/// What a `setClosedLidMode` request is known to have done.
public enum ClosedLidModeChangeOutcome: Equatable, Sendable {
    case succeeded
    /// `pmset` reported a failure, so the setting did not change.
    case failed
    /// No answer came back, so the setting may or may not have changed.
    case unknown

    /// Only a failure `pmset` itself reported counts as definite; anything
    /// else may have applied the change.
    public init(error: Error?) {
        switch error {
        case nil:
            self = .succeeded
        case PMSetError.commandFailed?:
            self = .failed
        default:
            self = .unknown
        }
    }
}

/// Turns closed-lid mode back off when the app that enabled it dies first.
///
/// `pmset -a disablesleep` is a machine-wide setting that outlives the app.
/// The app restores it on a normal quit, but a crash or a force quit skips
/// that, and the Mac then refuses to sleep until the app is opened again. The
/// helper outlives the app, so it watches the client that last enabled the
/// mode and restores when that process exits without restoring first.
///
/// A restore that fails once the client is gone is retried with a growing
/// delay until it succeeds, since nothing else is left to restore it. A new
/// enable or a successful disable takes over and stops the retries.
///
/// Not thread-safe: make every call, deliver every exit, and run every
/// scheduled retry on one serial queue.
public final class ClosedLidRestoreWatchdog {
    public typealias WatchProcessExit = (Int32, @escaping () -> Void) -> ProcessExitWatching
    public typealias ScheduleRetry = (TimeInterval, @escaping () -> Void) -> Void

    /// Delays between restore attempts; the last one repeats.
    public static let restoreRetryDelays: [TimeInterval] = [2, 10, 30, 120, 600]

    private struct ArmedWatch {
        let processID: Int32
        let watch: ProcessExitWatching
        let token: UUID
    }

    private let restore: () -> Bool
    private let readClosedLidStatus: () -> ClosedLidStatus
    private let watchProcessExit: WatchProcessExit
    private let scheduleRetry: ScheduleRetry
    private var armed: ArmedWatch?
    /// Identifies the restore still being retried, if any.
    private var pendingRestore: UUID?

    /// - Parameters:
    ///   - restore: Turns closed-lid mode off and reports whether it worked.
    ///   - readClosedLidStatus: Reads the current setting, for an enable that
    ///     `pmset` rejected.
    public init(
        restore: @escaping () -> Bool,
        readClosedLidStatus: @escaping () -> ClosedLidStatus,
        watchProcessExit: @escaping WatchProcessExit,
        scheduleRetry: @escaping ScheduleRetry
    ) {
        self.restore = restore
        self.readClosedLidStatus = readClosedLidStatus
        self.watchProcessExit = watchProcessExit
        self.scheduleRetry = scheduleRetry
    }

    /// Records a `setClosedLidMode` request the helper just ran.
    ///
    /// An enable arms the watch unless `pmset` reported that it failed, since
    /// one that timed out may still have applied it. An enable that failed
    /// outright changed nothing, so it leaves any earlier watch in place,
    /// unless the mode is on anyway: the app re-sends the enable to a new
    /// helper for a mode it already owns, and that mode still needs a watch
    /// when `pmset` rejects the repeat. A read that does not report the
    /// setting counts as on, since only a mode known to be off can do without
    /// the watch. Only a disable that succeeded disarms it.
    public func closedLidModeChangeAttempted(
        enabled: Bool,
        outcome: ClosedLidModeChangeOutcome,
        clientProcessID: Int32
    ) {
        guard enabled else {
            if outcome == .succeeded {
                disarm()
                pendingRestore = nil
            }
            return
        }

        guard outcome != .failed || readClosedLidStatus() != .disabled else {
            return
        }

        pendingRestore = nil

        guard armed?.processID != clientProcessID else {
            return
        }

        disarm()
        let token = UUID()
        let watch = watchProcessExit(clientProcessID) { [weak self] in
            self?.clientExited(token: token)
        }
        armed = ArmedWatch(processID: clientProcessID, watch: watch, token: token)
    }

    private func clientExited(token: UUID) {
        guard armed?.token == token else {
            return
        }

        disarm()
        let restoreID = UUID()
        pendingRestore = restoreID
        attemptRestore(restoreID: restoreID, attempt: 0)
    }

    private func attemptRestore(restoreID: UUID, attempt: Int) {
        guard pendingRestore == restoreID else {
            return
        }

        if restore() {
            pendingRestore = nil
            return
        }

        let delays = Self.restoreRetryDelays
        let delay = delays[min(attempt, delays.count - 1)]
        scheduleRetry(delay) { [weak self] in
            self?.attemptRestore(restoreID: restoreID, attempt: attempt + 1)
        }
    }

    private func disarm() {
        armed?.watch.cancel()
        armed = nil
    }
}

/// Reports a process exit through a dispatch source, at most once.
public final class DispatchProcessExitWatch: ProcessExitWatching {
    private let source: DispatchSourceProcess
    private var handler: (() -> Void)?

    public init(processID: Int32, queue: DispatchQueue, handler: @escaping () -> Void) {
        self.handler = handler
        self.source = DispatchSource.makeProcessSource(identifier: processID, eventMask: .exit, queue: queue)
        source.setEventHandler { [weak self] in
            self?.fire()
        }
        source.resume()

        // A process that exited before the source was armed never delivers
        // `.exit`, so check once after arming.
        if kill(processID, 0) == -1, errno == ESRCH {
            queue.async { [weak self] in
                self?.fire()
            }
        }
    }

    deinit {
        source.cancel()
    }

    /// Call on `queue`, like everything else that touches the watch.
    public func cancel() {
        handler = nil
        source.cancel()
    }

    private func fire() {
        guard let handler else {
            return
        }

        self.handler = nil
        source.cancel()
        handler()
    }
}
