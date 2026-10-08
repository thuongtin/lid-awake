import LidAwakeCore
import XCTest

final class ClosedLidRestoreWatchdogTests: XCTestCase {
    func testRestoresWhenTheClientThatEnabledClosedLidModeExits() {
        let harness = WatchdogHarness()

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, succeeded: true, clientProcessID: 42)
        harness.watcher.exit(42)

        XCTAssertEqual(harness.restoreCount, 1)
    }

    func testArmsEvenWhenTheEnableReportedFailure() {
        // A timed-out pmset may still have applied the change.
        let harness = WatchdogHarness()

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, succeeded: false, clientProcessID: 42)
        harness.watcher.exit(42)

        XCTAssertEqual(harness.restoreCount, 1)
    }

    func testDisarmsAfterASuccessfulRestoreByTheApp() {
        let harness = WatchdogHarness()

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, succeeded: true, clientProcessID: 42)
        harness.watchdog.closedLidModeChangeAttempted(enabled: false, succeeded: true, clientProcessID: 42)
        harness.watcher.exit(42)

        XCTAssertEqual(harness.restoreCount, 0)
        XCTAssertEqual(harness.watcher.cancelledProcessIDs, [42])
    }

    func testStaysArmedWhenTheAppsRestoreFails() {
        let harness = WatchdogHarness()

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, succeeded: true, clientProcessID: 42)
        harness.watchdog.closedLidModeChangeAttempted(enabled: false, succeeded: false, clientProcessID: 42)
        harness.watcher.exit(42)

        XCTAssertEqual(harness.restoreCount, 1)
    }

    func testFollowsTheMostRecentClientThatEnabled() {
        let harness = WatchdogHarness()

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, succeeded: true, clientProcessID: 42)
        harness.watchdog.closedLidModeChangeAttempted(enabled: true, succeeded: true, clientProcessID: 43)
        harness.watcher.exit(42)

        XCTAssertEqual(harness.restoreCount, 0)
        XCTAssertEqual(harness.watcher.cancelledProcessIDs, [42])

        harness.watcher.exit(43)

        XCTAssertEqual(harness.restoreCount, 1)
    }

    func testRestoresOnlyOncePerEnable() {
        let harness = WatchdogHarness()

        harness.watchdog.closedLidModeChangeAttempted(enabled: true, succeeded: true, clientProcessID: 42)
        harness.watcher.exit(42)
        harness.watcher.exit(42)

        XCTAssertEqual(harness.restoreCount, 1)
    }

    func testIgnoresADisableFromAClientThatNeverEnabled() {
        let harness = WatchdogHarness()

        harness.watchdog.closedLidModeChangeAttempted(enabled: false, succeeded: true, clientProcessID: 42)

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
    private(set) var restoreCount = 0
    lazy var watchdog = ClosedLidRestoreWatchdog(
        restore: { [unowned self] in
            restoreCount += 1
        },
        watchProcessExit: { [watcher] processID, handler in
            watcher.watch(processID, handler: handler)
        }
    )
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
