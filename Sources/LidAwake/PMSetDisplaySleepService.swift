import LidAwakeCore
import Foundation

enum DisplaySleepError: LocalizedError, Equatable {
    case commandFailed(Int32, String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case let .commandFailed(status, output):
            output.isEmpty ? "displaysleepnow failed with exit code \(status)." : output
        case .timedOut:
            "pmset displaysleepnow did not finish in time."
        }
    }

    init?(result: ProcessResult) {
        if result.timedOut {
            self = .timedOut
        } else if result.status != 0 {
            self = .commandFailed(result.status, result.output)
        } else {
            return nil
        }
    }
}

/// Asks `pmset` to sleep the displays without waiting for it.
///
/// The coordinator calls this from the main actor's side-effects timer, so the
/// command runs on `blockingWork` and a failure arrives later through
/// `failureHandler`.
final class PMSetDisplaySleepService: DisplaySleeping {
    static let commandTimeout: TimeInterval = 2

    var failureHandler: (@MainActor (String) -> Void)?

    private let blockingWork: BlockingWorkPerforming
    private let runCommand: () -> ProcessResult
    /// Touched only on the main actor, where requests start and finish.
    private var isRunning = false

    init(
        blockingWork: BlockingWorkPerforming = BackgroundBlockingWork(label: "com.thuongtin.LidAwake.display-sleep"),
        runCommand: @escaping () -> ProcessResult = {
            ProcessRunner.run(
                "/usr/bin/pmset",
                arguments: ["displaysleepnow"],
                timeout: PMSetDisplaySleepService.commandTimeout
            )
        }
    ) {
        self.blockingWork = blockingWork
        self.runCommand = runCommand
    }

    func sleepDisplaysNow() throws {
        // A request already out covers this one; stacking more behind a stuck
        // `pmset` would only run them late.
        guard !isRunning else {
            return
        }

        isRunning = true
        blockingWork.perform(runCommand) { [weak self] result in
            guard let self else {
                return
            }

            isRunning = false
            if let error = DisplaySleepError(result: result) {
                failureHandler?(error.localizedDescription)
            }
        }
    }
}
