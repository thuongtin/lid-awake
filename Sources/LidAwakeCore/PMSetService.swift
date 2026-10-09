import Foundation

public enum PMSetError: LocalizedError, Equatable {
    /// `pmset` exited and reported a failure.
    case commandFailed(Int32, String)
    /// `pmset` was stopped before it exited, so it may have applied the change.
    case timedOut(String)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(status, output):
            output.isEmpty ? "pmset failed with exit code \(status)." : output
        case let .timedOut(output):
            output
        }
    }
}

public struct PMSetService: Sendable {
    public typealias ProcessRunning = @Sendable (String, [String], TimeInterval) -> ProcessResult

    /// Reading settings normally takes milliseconds. The app reads on the main
    /// actor, so a hung `pmset` must give up well before the app looks frozen.
    public static let statusReadTimeout: TimeInterval = 2
    /// Short enough for the helper to answer inside the app's XPC deadline.
    public static let closedLidChangeTimeout: TimeInterval = 3

    private let runProcess: ProcessRunning

    public init(runProcess: @escaping ProcessRunning = { ProcessRunner.run($0, arguments: $1, timeout: $2) }) {
        self.runProcess = runProcess
    }

    public func readClosedLidStatus() -> ClosedLidStatus {
        let current = runProcess("/usr/bin/pmset", ["-g"], Self.statusReadTimeout)
        guard !current.timedOut else {
            return .notReported
        }

        if current.status == 0 {
            let status = Self.parseClosedLidStatus(from: current.output)
            if status != .notReported {
                return status
            }
        }

        let custom = runProcess("/usr/bin/pmset", ["-g", "custom"], Self.statusReadTimeout)
        guard custom.status == 0 else {
            return .notReported
        }

        return Self.parseClosedLidStatus(from: custom.output)
    }

    public func setClosedLidMode(enabled: Bool) throws {
        let value = enabled ? "1" : "0"
        let result = runProcess("/usr/bin/pmset", ["-a", "disablesleep", value], Self.closedLidChangeTimeout)
        guard !result.timedOut else {
            throw PMSetError.timedOut(result.output)
        }

        guard result.status == 0, !Self.isPermissionFailureOutput(result.output) else {
            throw PMSetError.commandFailed(result.status, result.output)
        }
    }

    public static func isPermissionFailureOutput(_ output: String) -> Bool {
        let normalized = output.lowercased()
        return normalized.contains("must be run as root")
            || normalized.contains("operation not permitted")
            || normalized.contains("permission denied")
    }

    public static func parseClosedLidStatus(from output: String) -> ClosedLidStatus {
        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else {
                continue
            }

            switch parts[0] {
            case "SleepDisabled", "disablesleep":
                return parts[1] == "1" ? .enabled : .disabled
            default:
                continue
            }
        }

        return .notReported
    }
}
