import LidAwakeCore
import Foundation

enum DisplaySleepError: LocalizedError, Equatable {
    case launchFailed(String)
    case commandFailed(Int32, String)

    var errorDescription: String? {
        switch self {
        case let .launchFailed(message):
            message
        case let .commandFailed(status, output):
            output.isEmpty ? "displaysleepnow failed with exit code \(status)." : output
        }
    }
}

final class PMSetDisplaySleepService: DisplaySleeping {
    func sleepDisplaysNow() throws {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw DisplaySleepError.launchFailed(error.localizedDescription)
        }

        let output = read(stdout) + read(stderr)
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw DisplaySleepError.commandFailed(process.terminationStatus, trimmedOutput)
        }
    }

    private func read(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
