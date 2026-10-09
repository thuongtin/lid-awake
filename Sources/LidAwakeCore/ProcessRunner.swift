import Foundation

public struct ProcessResult: Equatable, Sendable {
    public let status: Int32
    public let output: String
    public let timedOut: Bool

    public init(status: Int32, output: String, timedOut: Bool) {
        self.status = status
        self.output = output
        self.timedOut = timedOut
    }
}

/// Runs a short-lived command with a hard deadline.
///
/// Callers include the main actor, so a child that never exits must not be
/// able to hold the caller with it. `pmset` has been seen hanging for minutes,
/// and waiting on it without a deadline froze the whole app until it was force
/// quit.
public enum ProcessRunner {
    /// How long a terminated child gets to exit before it is killed outright.
    static let terminationGracePeriod: TimeInterval = 0.5

    public static func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> ProcessResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let exited = DispatchSemaphore(value: 0)

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { _ in
            exited.signal()
        }

        do {
            try process.run()
        } catch {
            return ProcessResult(status: 1, output: error.localizedDescription, timedOut: false)
        }

        // Drain both pipes while the child runs. A child that fills a pipe
        // buffer blocks on write until someone reads it, so reading only after
        // exit can deadlock on any output larger than the buffer.
        let collector = OutputCollector()
        let reads = DispatchGroup()
        for (index, pipe) in [stdout, stderr].enumerated() {
            reads.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                collector.set(pipe.fileHandleForReading.readDataToEndOfFile(), at: index)
                reads.leave()
            }
        }

        guard exited.wait(timeout: .now() + timeout) == .success else {
            stop(process, exited: exited)
            return ProcessResult(
                status: -1,
                output: "\(executable) did not finish within \(timeout) seconds.",
                timedOut: true
            )
        }

        // A grandchild that inherited the pipes can keep them open after the
        // child exits, so the reads get a bound of their own.
        _ = reads.wait(timeout: .now() + terminationGracePeriod)
        return ProcessResult(
            status: process.terminationStatus,
            output: collector.joinedOutput().trimmingCharacters(in: .whitespacesAndNewlines),
            timedOut: false
        )
    }

    private static func stop(_ process: Process, exited: DispatchSemaphore) {
        process.terminate()
        guard exited.wait(timeout: .now() + terminationGracePeriod) == .timedOut else {
            return
        }

        // Do not wait again: a child stuck in the kernel can ignore even
        // SIGKILL for a while, and the caller has already waited long enough.
        kill(process.processIdentifier, SIGKILL)
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [Data] = [Data(), Data()]

    func set(_ data: Data, at index: Int) {
        lock.lock()
        chunks[index] = data
        lock.unlock()
    }

    func joinedOutput() -> String {
        lock.lock()
        let data = chunks.reduce(Data(), +)
        lock.unlock()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
