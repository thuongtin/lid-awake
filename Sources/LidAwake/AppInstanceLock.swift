import Foundation

/// Keeps the command-line helper changes and a running app apart.
///
/// Every running copy of the app holds a shared lock on one file for as long
/// as it runs, and `--helper-remove` and `--helper-repair` take it exclusively.
/// A command refuses while any copy holds it, and a copy that launches while a
/// command runs waits for the command to finish before it starts, so neither
/// can send the helper a change the other cannot see. The kernel drops the
/// lock when the process exits, crash included.
final class AppInstanceLock {
    enum Mode {
        case shared
        case exclusive

        fileprivate var operation: Int32 {
            switch self {
            case .shared:
                LOCK_SH
            case .exclusive:
                LOCK_EX
            }
        }
    }

    enum Outcome {
        case acquired(AppInstanceLock)
        /// Another process holds a lock that conflicts with this one.
        case busy
        /// The lock file could not be opened or locked.
        case unavailable(String)
    }

    static var defaultURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory
            .appendingPathComponent("com.thuongtin.LidAwake", isDirectory: true)
            .appendingPathComponent("app-instance.lock")
    }

    private let fileDescriptor: Int32

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        close(fileDescriptor)
    }

    /// Takes the lock, retrying until `timeout` while another process holds a
    /// conflicting one.
    static func acquire(
        _ mode: Mode,
        at url: URL = defaultURL,
        waitingUpTo timeout: TimeInterval = 0
    ) -> Outcome {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return .unavailable(error.localizedDescription)
        }

        let fileDescriptor = open(url.path, O_RDONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard fileDescriptor >= 0 else {
            return .unavailable(String(cString: strerror(errno)))
        }

        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if flock(fileDescriptor, mode.operation | LOCK_NB) == 0 {
                return .acquired(AppInstanceLock(fileDescriptor: fileDescriptor))
            }

            let lockError = errno
            guard lockError == EWOULDBLOCK || lockError == EINTR else {
                close(fileDescriptor)
                return .unavailable(String(cString: strerror(lockError)))
            }

            guard Date() < deadline else {
                close(fileDescriptor)
                return .busy
            }

            Thread.sleep(forTimeInterval: 0.1)
        }
    }
}
