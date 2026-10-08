import LidAwakeCore
import XCTest

final class ClosedLidLockCoordinatorTests: XCTestCase {
    func testDoesNotLockWhenFirstObservedStateIsAlreadyClosed() {
        let clamshellStateReader = FakeLockClamshellStateReader(state: .closed)
        let deviceLocker = FakeDeviceLocker()
        let coordinator = ClosedLidLockCoordinator(
            clamshellStateReader: clamshellStateReader,
            deviceLocker: deviceLocker
        )
        var settings = UserSettings.defaults
        settings.lockScreenWhenLidCloses = true

        let firstAction = coordinator.update(settings: settings)
        let secondAction = coordinator.update(settings: settings)

        XCTAssertEqual(firstAction, .none)
        XCTAssertEqual(secondAction, .none)
        XCTAssertEqual(deviceLocker.lockCount, 0)
    }

    func testLocksWhenLidTransitionsFromOpenToClosed() {
        let clamshellStateReader = FakeLockClamshellStateReader(state: .open)
        let deviceLocker = FakeDeviceLocker()
        let coordinator = ClosedLidLockCoordinator(
            clamshellStateReader: clamshellStateReader,
            deviceLocker: deviceLocker
        )
        var settings = UserSettings.defaults
        settings.lockScreenWhenLidCloses = true

        let initialAction = coordinator.update(settings: settings)
        clamshellStateReader.state = .closed
        let firstAction = coordinator.update(settings: settings)
        let secondAction = coordinator.update(settings: settings)

        XCTAssertEqual(initialAction, .none)
        XCTAssertEqual(firstAction, .requestedLock)
        XCTAssertEqual(secondAction, .none)
        XCTAssertEqual(deviceLocker.lockCount, 1)
    }

    func testDoesNotLockWhenStateMovesFromUnavailableToClosed() {
        let clamshellStateReader = FakeLockClamshellStateReader(state: .unavailable)
        let deviceLocker = FakeDeviceLocker()
        let coordinator = ClosedLidLockCoordinator(
            clamshellStateReader: clamshellStateReader,
            deviceLocker: deviceLocker
        )
        var settings = UserSettings.defaults
        settings.lockScreenWhenLidCloses = true

        let initialAction = coordinator.update(settings: settings)
        clamshellStateReader.state = .closed
        let closeAction = coordinator.update(settings: settings)

        XCTAssertEqual(initialAction, .none)
        XCTAssertEqual(closeAction, .none)
        XCTAssertEqual(deviceLocker.lockCount, 0)
    }

    func testOpenLidResetsLockRequest() {
        let clamshellStateReader = FakeLockClamshellStateReader(state: .open)
        let deviceLocker = FakeDeviceLocker()
        let coordinator = ClosedLidLockCoordinator(
            clamshellStateReader: clamshellStateReader,
            deviceLocker: deviceLocker
        )
        var settings = UserSettings.defaults
        settings.lockScreenWhenLidCloses = true

        _ = coordinator.update(settings: settings)
        clamshellStateReader.state = .closed
        _ = coordinator.update(settings: settings)
        clamshellStateReader.state = .open
        _ = coordinator.update(settings: settings)
        clamshellStateReader.state = .closed
        let action = coordinator.update(settings: settings)

        XCTAssertEqual(action, .requestedLock)
        XCTAssertEqual(deviceLocker.lockCount, 2)
    }

    func testDoesNotLockWhenOptionIsDisabled() {
        let clamshellStateReader = FakeLockClamshellStateReader(state: .closed)
        let deviceLocker = FakeDeviceLocker()
        let coordinator = ClosedLidLockCoordinator(
            clamshellStateReader: clamshellStateReader,
            deviceLocker: deviceLocker
        )

        let action = coordinator.update(settings: .defaults)

        XCTAssertEqual(action, .none)
        XCTAssertEqual(deviceLocker.lockCount, 0)
    }

    func testDoesNotLockWhenAppIsDisabled() {
        let clamshellStateReader = FakeLockClamshellStateReader(state: .closed)
        let deviceLocker = FakeDeviceLocker()
        let coordinator = ClosedLidLockCoordinator(
            clamshellStateReader: clamshellStateReader,
            deviceLocker: deviceLocker
        )
        var settings = UserSettings.defaults
        settings.enabled = false
        settings.lockScreenWhenLidCloses = true

        let action = coordinator.update(settings: settings)

        XCTAssertEqual(action, .none)
        XCTAssertEqual(deviceLocker.lockCount, 0)
    }

    func testReturnsFailureWhenLockFails() {
        let clamshellStateReader = FakeLockClamshellStateReader(state: .open)
        let deviceLocker = FakeDeviceLocker()
        deviceLocker.error = NSError(domain: "ScreenLock", code: 1)
        let coordinator = ClosedLidLockCoordinator(
            clamshellStateReader: clamshellStateReader,
            deviceLocker: deviceLocker
        )
        var settings = UserSettings.defaults
        settings.lockScreenWhenLidCloses = true

        _ = coordinator.update(settings: settings)
        clamshellStateReader.state = .closed
        let action = coordinator.update(settings: settings)

        guard case let .failed(message) = action else {
            XCTFail("Expected screen lock failure")
            return
        }
        XCTAssertTrue(message.contains("ScreenLock"))
        XCTAssertEqual(deviceLocker.lockCount, 1)
    }
}

extension ClosedLidLockCoordinatorTests {
    private func lockOnClose(
        lockState: LockScreenStateReader
    ) -> (ClosedLidLockCoordinator, FakeLockClamshellStateReader, UserSettings) {
        let clamshellStateReader = FakeLockClamshellStateReader(state: .open)
        let coordinator = ClosedLidLockCoordinator(
            clamshellStateReader: clamshellStateReader,
            deviceLocker: FakeDeviceLocker(),
            screenLockStateReader: lockState
        )
        var settings = UserSettings.defaults
        settings.lockScreenWhenLidCloses = true
        coordinator.update(settings: settings)
        clamshellStateReader.state = .closed
        XCTAssertEqual(coordinator.update(settings: settings), .requestedLock)
        return (coordinator, clamshellStateReader, settings)
    }

    func testReportsALockThatNeverHappened() {
        let lockState = LockScreenStateReader(state: .unlocked)
        let (coordinator, _, settings) = lockOnClose(lockState: lockState)

        XCTAssertEqual(coordinator.update(settings: settings), .none)
        XCTAssertEqual(coordinator.update(settings: settings), .none)
        XCTAssertEqual(
            coordinator.update(settings: settings),
            .failed(ClosedLidLockCoordinator.lockNotObservedMessage)
        )
        // Reported once per close, not on every tick after.
        XCTAssertEqual(coordinator.update(settings: settings), .none)
    }

    func testALockThatLandsIsNotReported() {
        let lockState = LockScreenStateReader(state: .unlocked)
        let (coordinator, _, settings) = lockOnClose(lockState: lockState)

        XCTAssertEqual(coordinator.update(settings: settings), .none)
        lockState.state = .locked
        for _ in 0..<5 {
            XCTAssertEqual(coordinator.update(settings: settings), .none)
        }
    }

    func testAnUnreadableLockStateIsNotReported() {
        let lockState = LockScreenStateReader(state: .unavailable)
        let (coordinator, _, settings) = lockOnClose(lockState: lockState)

        for _ in 0..<5 {
            XCTAssertEqual(coordinator.update(settings: settings), .none)
        }
    }

    func testOpeningTheLidStopsTheCheck() {
        let lockState = LockScreenStateReader(state: .unlocked)
        let (coordinator, clamshell, settings) = lockOnClose(lockState: lockState)

        clamshell.state = .open
        for _ in 0..<5 {
            XCTAssertEqual(coordinator.update(settings: settings), .none)
        }
    }
}

private final class LockScreenStateReader: ScreenLockStateReading {
    var state: ScreenLockState

    init(state: ScreenLockState) {
        self.state = state
    }

    func screenLockState() -> ScreenLockState {
        state
    }
}

private final class FakeLockClamshellStateReader: ClamshellStateReading {
    var state: ClamshellState

    init(state: ClamshellState) {
        self.state = state
    }

    func clamshellState() -> ClamshellState {
        state
    }
}

private final class FakeDeviceLocker: DeviceLocking {
    var lockCount = 0
    var error: Error?

    func lockScreenNow() throws {
        lockCount += 1
        if let error {
            throw error
        }
    }
}
