import LidAwakeCore
import XCTest

final class ClosedLidRestoreWatchdogTests: XCTestCase {
    func testRestoresWhenTheClientThatEnabledClosedLidModeExits() {
        let harness = WatchdogHarness()

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .succeeded, clientProcessID: 42)
        harness.watcher.exit(42)

        XCTAssertEqual(harness.restoreCount, 1)
    }

    func testArmsWhenTheEnableOutcomeIsUnknown() {
        // A timed-out pmset may still have applied the change.
        let harness = WatchdogHarness()

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .unknown, clientProcessID: 42)
        harness.watcher.exit(42)

        XCTAssertEqual(harness.restoreCount, 1)
    }

    func testDoesNotArmWhenPMSetReportedTheEnableFailed() {
        // The setting did not change, so someone else may turn it on later.
        let harness = WatchdogHarness()

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .failed, clientProcessID: 42)
        harness.watcher.exit(42)

        XCTAssertEqual(harness.restoreCount, 0)
    }

    func testArmsWhenARejectedEnableFindsTheModeAlreadyOn() {
        // A re-arm for a mode the app already owns: the setting is on whatever
        // `pmset` said about the repeat, so it still needs restoring.
        let harness = WatchdogHarness()
        harness.closedLidStatus = .enabled

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .failed, clientProcessID: 42)
        harness.watcher.exit(42)

        XCTAssertEqual(harness.restoreCount, 1)
    }

    func testArmsWhenARejectedEnableCannotReadTheMode() {
        let harness = WatchdogHarness()
        harness.closedLidStatus = .notReported

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .failed, clientProcessID: 42)
        harness.watcher.exit(42)

        XCTAssertEqual(harness.restoreCount, 1)
    }

    func testReadsTheModeOnlyForARejectedEnable() {
        let harness = WatchdogHarness()

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .succeeded, clientProcessID: 42)
        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .unknown, clientProcessID: 43)
        harness.watchdog.closedLidModeChangeAttempted(enabled: false, outcome: .failed, clientProcessID: 43)
        XCTAssertEqual(harness.statusReadCount, 0)

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .failed, clientProcessID: 44)
        XCTAssertEqual(harness.statusReadCount, 1)
    }

    func testAFailedEnableKeepsTheEarlierWatch() {
        let harness = WatchdogHarness()

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .succeeded, clientProcessID: 42)
        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .failed, clientProcessID: 43)
        harness.watcher.exit(42)

        XCTAssertEqual(harness.restoreCount, 1)
    }

    func testOnlyAFailureReportedByPMSetCountsAsDefinite() {
        XCTAssertEqual(ClosedLidModeChangeOutcome(error: nil), .succeeded)
        XCTAssertEqual(ClosedLidModeChangeOutcome(error: PMSetError.commandFailed(1, "denied")), .failed)
        XCTAssertEqual(ClosedLidModeChangeOutcome(error: PMSetError.timedOut("hung")), .unknown)
        XCTAssertEqual(ClosedLidModeChangeOutcome(error: CocoaError(.fileNoSuchFile)), .unknown)
    }

    func testDisarmsAfterASuccessfulRestoreByTheApp() {
        let harness = WatchdogHarness()

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .succeeded, clientProcessID: 42)
        harness.watchdog.closedLidModeChangeAttempted(enabled: false, outcome: .succeeded, clientProcessID: 42)
        harness.watcher.exit(42)

        XCTAssertEqual(harness.restoreCount, 0)
        XCTAssertEqual(harness.watcher.cancelledProcessIDs, [42])
    }

    func testStaysArmedWhenTheAppsRestoreFails() {
        let harness = WatchdogHarness()

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .succeeded, clientProcessID: 42)
        harness.watchdog.closedLidModeChangeAttempted(enabled: false, outcome: .failed, clientProcessID: 42)
        harness.watcher.exit(42)

        XCTAssertEqual(harness.restoreCount, 1)
    }

    func testFollowsTheMostRecentClientThatEnabled() {
        let harness = WatchdogHarness()

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .succeeded, clientProcessID: 42)
        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .succeeded, clientProcessID: 43)
        harness.watcher.exit(42)

        XCTAssertEqual(harness.restoreCount, 0)
        XCTAssertEqual(harness.watcher.cancelledProcessIDs, [42])

        harness.watcher.exit(43)

        XCTAssertEqual(harness.restoreCount, 1)
    }

    func testRestoresOnlyOncePerEnable() {
        let harness = WatchdogHarness()

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .succeeded, clientProcessID: 42)
        harness.watcher.exit(42)
        harness.watcher.exit(42)

        XCTAssertEqual(harness.restoreCount, 1)
    }

    func testRetriesARestoreThatFailedAfterTheClientExited() {
        let harness = WatchdogHarness()
        harness.restoreResults = [false, false, true]

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .succeeded, clientProcessID: 42)
        harness.watcher.exit(42)

        XCTAssertEqual(harness.restoreCount, 1)
        XCTAssertEqual(harness.scheduler.delays, [2])

        harness.scheduler.runNext()
        XCTAssertEqual(harness.restoreCount, 2)
        XCTAssertEqual(harness.scheduler.delays, [2, 10])

        harness.scheduler.runNext()
        XCTAssertEqual(harness.restoreCount, 3)
        XCTAssertTrue(harness.scheduler.pending.isEmpty)
    }

    func testKeepsRetryingAtTheLongestDelay() {
        let harness = WatchdogHarness()
        harness.restoreResults = []

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .succeeded, clientProcessID: 42)
        harness.watcher.exit(42)
        for _ in 0..<7 {
            harness.scheduler.runNext()
        }

        XCTAssertEqual(harness.restoreCount, 8)
        XCTAssertEqual(harness.scheduler.delays, [2, 10, 30, 120, 600, 600, 600, 600])
    }

    func testANewEnableStopsPendingRetries() {
        let harness = WatchdogHarness()
        harness.restoreResults = []

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .succeeded, clientProcessID: 42)
        harness.watcher.exit(42)
        // A relaunched app owns the mode again and restores it itself.
        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .succeeded, clientProcessID: 43)
        harness.scheduler.runNext()

        XCTAssertEqual(harness.restoreCount, 1)
        XCTAssertTrue(harness.scheduler.pending.isEmpty)
    }

    func testASuccessfulDisableStopsPendingRetries() {
        let harness = WatchdogHarness()
        harness.restoreResults = []

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .succeeded, clientProcessID: 42)
        harness.watcher.exit(42)
        harness.watchdog.closedLidModeChangeAttempted(enabled: false, outcome: .succeeded, clientProcessID: 43)
        harness.scheduler.runNext()

        XCTAssertEqual(harness.restoreCount, 1)
        XCTAssertTrue(harness.scheduler.pending.isEmpty)
    }

    func testWatchesAClientWhoseDisableFailedWhileTheModeIsOn() {
        // A command-line repair restores through a new helper that has no
        // watch, then exits, so the helper keeps retrying after it.
        let harness = WatchdogHarness()
        harness.closedLidStatus = .enabled
        harness.restoreResults = [false]

        harness.watchdog.closedLidModeChangeAttempted(enabled: false, outcome: .failed, clientProcessID: 42)
        harness.watcher.exit(42)
        harness.scheduler.runNext()

        XCTAssertEqual(harness.restoreCount, 2)
    }

    func testAFailedDisableKeepsTheWatchOnTheClientThatEnabled() {
        let harness = WatchdogHarness()
        harness.closedLidStatus = .enabled

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, outcome: .succeeded, clientProcessID: 42)
        harness.watchdog.closedLidModeChangeAttempted(enabled: false, outcome: .failed, clientProcessID: 43)
        harness.watcher.exit(43)
        XCTAssertEqual(harness.restoreCount, 0)

        harness.watcher.exit(42)
        XCTAssertEqual(harness.restoreCount, 1)
    }

    func testDoesNotWatchAFailedDisableWhenTheModeIsOff() {
        let harness = WatchdogHarness()
        harness.closedLidStatus = .disabled

        harness.watchdog.closedLidModeChangeAttempted(enabled: false, outcome: .failed, clientProcessID: 42)

        XCTAssertTrue(harness.watcher.watchedProcessIDs.isEmpty)
    }

    func testIgnoresADisableFromAClientThatNeverEnabled() {
        let harness = WatchdogHarness()

        harness.watchdog.closedLidModeChangeAttempted(enabled: false, outcome: .succeeded, clientProcessID: 42)

        XCTAssertTrue(harness.watcher.watchedProcessIDs.isEmpty)
        XCTAssertEqual(harness.restoreCount, 0)
    }

    func testDispatchWatchReportsAChildProcessExit() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.2"]
        try process.run()

        let exited = expectation(description: "exit observed")
        let watch = DispatchProcessExitWatch(
            processID: process.processIdentifier,
            queue: DispatchQueue(label: "ClosedLidRestoreWatchdogTests")
        ) {
            exited.fulfill()
        }

        wait(for: [exited], timeout: 5)
        watch.cancel()
    }

    func testDispatchWatchReportsAProcessThatIsAlreadyGone() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()

        let exited = expectation(description: "exit observed")
        let watch = DispatchProcessExitWatch(
            processID: process.processIdentifier,
            queue: DispatchQueue(label: "ClosedLidRestoreWatchdogTests")
        ) {
            exited.fulfill()
        }

        wait(for: [exited], timeout: 5)
        watch.cancel()
    }
}

private final class WatchdogHarness {
    let watcher = FakeProcessExitWatcher()
    let scheduler = FakeRetryScheduler()
    private(set) var restoreCount = 0
    /// Results handed out in order; once empty every restore fails. `nil`
    /// means every restore succeeds.
    var restoreResults: [Bool]?
    var closedLidStatus: ClosedLidStatus = .disabled
    private(set) var statusReadCount = 0
    lazy var watchdog = ClosedLidRestoreWatchdog(
        restore: { [unowned self] in
            restoreCount += 1
            guard restoreResults != nil else {
                return true
            }

            return restoreResults!.isEmpty ? false : restoreResults!.removeFirst()
        },
        readClosedLidStatus: { [unowned self] in
            statusReadCount += 1
            return closedLidStatus
        },
        watchProcessExit: { [watcher] processID, handler in
            watcher.watch(processID, handler: handler)
        },
        scheduleRetry: { [scheduler] delay, work in
            scheduler.schedule(after: delay, work)
        }
    )
}

private final class FakeRetryScheduler {
    private(set) var delays: [TimeInterval] = []
    private(set) var pending: [() -> Void] = []

    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) {
        delays.append(delay)
        pending.append(work)
    }

    func runNext() {
        guard !pending.isEmpty else {
            return
        }

        pending.removeFirst()()
    }
}

private final class FakeProcessExitWatcher {
    private(set) var watchedProcessIDs: [Int32] = []
    private(set) var cancelledProcessIDs: [Int32] = []
    private var handlers: [Int32: [() -> Void]] = [:]

    func watch(_ processID: Int32, handler: @escaping () -> Void) -> ProcessExitWatching {
        watchedProcessIDs.append(processID)
        handlers[processID, default: []].append(handler)
        return FakeWatch { [weak self] in
            self?.cancelledProcessIDs.append(processID)
        }
    }

    /// Delivers the exit to every watch ever made for the process, cancelled
    /// or not, so a stale handler that still acts shows up as a failure.
    func exit(_ processID: Int32) {
        handlers[processID]?.forEach { $0() }
    }
}

private final class FakeWatch: ProcessExitWatching {
    private let onCancel: () -> Void

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel()
    }
}
