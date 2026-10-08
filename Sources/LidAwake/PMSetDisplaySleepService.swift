import LidAwakeCore
import Foundation

enum DisplaySleepError: LocalizedError, Equatable {
    case commandFailed(Int32, String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(status, output):
            output.isEmpty ? "displaysleepnow failed with exit code \(status)." : output
        }
    }
}

final class PMSetDisplaySleepService: DisplaySleeping {
    /// Runs from the main actor's side-effects timer, so a hung `pmset` must
    /// not be able to hold it.
    static let commandTimeout: TimeInterval = 2

    func sleepDisplaysNow() throws {
        let result = ProcessRunner.run(
            "/usr/bin/pmset",
            arguments: ["displaysleepnow"],
            timeout: Self.commandTimeout
        )
        guard !result.timedOut, result.status == 0 else {
            throw DisplaySleepError.commandFailed(result.status, result.output)
        }
    }
}
