import Foundation

public protocol ProcessExitWatching: AnyObject {
    func cancel()
}

/// Turns closed-lid mode back off when the app that enabled it dies first.
///
/// `pmset -a disablesleep` is a machine-wide setting that outlives the app.
/// The app restores it on a normal quit, but a crash or a force quit skips
/// that, and the Mac then refuses to sleep until the app is opened again. The
/// helper outlives the app, so it watches the client that last enabled the
/// mode and restores when that process exits without restoring first.
///
/// Not thread-safe: make every call, and deliver every exit, on one serial
/// queue.
public final class ClosedLidRestoreWatchdog {
    public typealias WatchProcessExit = (Int32, @escaping () -> Void) -> ProcessExitWatching

    private struct ArmedWatch {
        let processID: Int32
        let watch: ProcessExitWatching
        let token: UUID
    }

    private let restore: () -> Void
    private let watchProcessExit: WatchProcessExit
    private var armed: ArmedWatch?

    public init(restore: @escaping () -> Void, watchProcessExit: @escaping WatchProcessExit) {
        self.restore = restore
        self.watchProcessExit = watchProcessExit
    }

    /// Records a `setClosedLidMode` request the helper just ran.
    ///
    /// Any enable attempt arms the watch, even one that reported failure,
    /// because a `pmset` that timed out may still have applied it. Only a
    /// disable that succeeded disarms it.
    public func closedLidModeChangeAttempted(enabled: Bool, succeeded: Bool, clientProcessID: Int32) {
        guard enabled else {
            if succeeded {
                disarm()
            }
            return
        }

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
        restore()
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
