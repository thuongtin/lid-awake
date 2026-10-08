@testable import LidAwake
import LidAwakeCore
import XCTest

@MainActor
final class SystemCommandServiceTests: XCTestCase {
    func testDisplaySleepReturnsBeforeTheCommandRuns() throws {
        let work = HeldBlockingWork()
        var runs = 0
        let service = PMSetDisplaySleepService(blockingWork: work) {
            runs += 1
            return ProcessResult(status: 0, output: "", timedOut: false)
        }
        var failures: [String] = []
        service.failureHandler = { failures.append($0) }

        try service.sleepDisplaysNow()

        XCTAssertEqual(runs, 0)
        XCTAssertEqual(work.pendingCount, 1)

        work.releaseAll()

        XCTAssertEqual(runs, 1)
        XCTAssertTrue(failures.isEmpty)
    }

    func testDisplaySleepReportsAFailureThatArrivesLater() throws {
        let work = HeldBlockingWork()
        let service = PMSetDisplaySleepService(blockingWork: work) {
            ProcessResult(status: 1, output: "", timedOut: false)
        }
        var failures: [String] = []
        service.failureHandler = { failures.append($0) }

        try service.sleepDisplaysNow()
        work.releaseAll()

        XCTAssertEqual(failures, ["displaysleepnow failed with exit code 1."])
    }

    func testDisplaySleepReportsATimeout() throws {
        let work = HeldBlockingWork()
        let service = PMSetDisplaySleepService(blockingWork: work) {
            ProcessResult(status: 15, output: "", timedOut: true)
        }
        var failures: [String] = []
        service.failureHandler = { failures.append($0) }

        try service.sleepDisplaysNow()
        work.releaseAll()

        XCTAssertEqual(failures, ["pmset displaysleepnow did not finish in time."])
    }

    func testDisplaySleepDoesNotStackRequestsBehindAStuckCommand() throws {
        let work = HeldBlockingWork()
        let service = PMSetDisplaySleepService(blockingWork: work) {
            ProcessResult(status: 0, output: "", timedOut: false)
        }

        XCTAssertTrue(try service.sleepDisplaysNow())
        XCTAssertFalse(try service.sleepDisplaysNow())
        XCTAssertEqual(work.pendingCount, 1)

        work.releaseAll()
        XCTAssertTrue(try service.sleepDisplaysNow())
        XCTAssertEqual(work.pendingCount, 1)
    }

    func testScreenLockCommandRunsOffTheCallerAndReportsFailure() throws {
        let work = HeldBlockingWork()
        var commands: [ScreenLockCommand] = []
        let command = ScreenLockCommand(executablePath: "/bin/lock", arguments: ["-suspend"])
        let service = SystemScreenLockService(
            shortcutPoster: FakeShortcutPoster(),
            resolveMethod: { .command(command) },
            blockingWork: work,
            runCommand: { command in
                commands.append(command)
                return ProcessResult(status: 2, output: "no session", timedOut: false)
            }
        )
        var failures: [String] = []
        service.failureHandler = { failures.append($0) }

        try service.lockScreenNow()
        XCTAssertTrue(commands.isEmpty)

        work.releaseAll()

        XCTAssertEqual(commands, [command])
        XCTAssertEqual(failures, ["no session"])
    }

    func testScreenLockShortcutStillThrowsWithoutAccessibility() {
        let poster = FakeShortcutPoster()
        poster.error = ScreenLockError.accessibilityPermissionRequired
        let work = HeldBlockingWork()
        let service = SystemScreenLockService(
            shortcutPoster: poster,
            resolveMethod: { .keyboardShortcut },
            blockingWork: work,
            runCommand: { _ in ProcessResult(status: 0, output: "", timedOut: false) }
        )

        XCTAssertThrowsError(try service.lockScreenNow()) { error in
            XCTAssertEqual(error as? ScreenLockError, .accessibilityPermissionRequired)
        }
        XCTAssertEqual(work.pendingCount, 0)
    }
}

private final class FakeShortcutPoster: ScreenLockShortcutPosting {
    var error: Error?

    func postLockScreenShortcut() throws {
        if let error {
            throw error
        }
    }
}
