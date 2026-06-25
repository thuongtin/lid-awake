import Foundation

public enum PMSetError: LocalizedError, Equatable {
    case launchFailed(String)
    case commandFailed(Int32, String)

    public var errorDescription: String? {
        switch self {
        case let .launchFailed(message):
            message
        case let .commandFailed(status, output):
            output.isEmpty ? "pmset failed with exit code \(status)." : output
        }
    }
}

public struct PMSetService: Sendable {
    public init() {}

    public func readClosedLidStatus() -> ClosedLidStatus {
        let current = runProcess("/usr/bin/pmset", arguments: ["-g"])
        if current.status == 0 {
            let status = Self.parseClosedLidStatus(from: current.output)
            if status != .notReported {
                return status
            }
        }

        let custom = runProcess("/usr/bin/pmset", arguments: ["-g", "custom"])
        guard custom.status == 0 else {
            return .notReported
        }

        return Self.parseClosedLidStatus(from: custom.output)
    }

    public func setClosedLidMode(enabled: Bool) throws {
        let value = enabled ? "1" : "0"
        let result = runProcess("/usr/bin/pmset", arguments: ["-a", "disablesleep", value])

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

    private func runProcess(_ executable: String, arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (1, PMSetError.launchFailed(error.localizedDescription).localizedDescription)
        }

        let output = read(stdout) + read(stderr)
        return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func read(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
