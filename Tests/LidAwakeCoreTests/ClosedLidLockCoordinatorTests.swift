import LidAwakeCore
import XCTest

final class ClosedLidLockCoordinatorTests: XCTestCase {
    func testDefaultLocksOnceForSameClosure() {
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

        XCTAssertEqual(firstAction, .requestedLock)
        XCTAssertEqual(secondAction, .none)
        XCTAssertEqual(deviceLocker.lockCount, 1)
    }

    func testRetriesLockDuringClosedLidTransitionThenStops() {
        let clamshellStateReader = FakeLockClamshellStateReader(state: .closed)
        let deviceLocker = FakeDeviceLocker()
        let coordinator = ClosedLidLockCoordinator(
            clamshellStateReader: clamshellStateReader,
            deviceLocker: deviceLocker,
            maximumLockRequests: 3
        )
        var settings = UserSettings.defaults
        settings.lockScreenWhenLidCloses = true

        let firstAction = coordinator.update(settings: settings)
        let secondAction = coordinator.update(settings: settings)
        let thirdAction = coordinator.update(settings: settings)
        let fourthAction = coordinator.update(settings: settings)

        XCTAssertEqual(firstAction, .requestedLock)
        XCTAssertEqual(secondAction, .requestedLock)
        XCTAssertEqual(thirdAction, .requestedLock)
        XCTAssertEqual(fourthAction, .none)
        XCTAssertEqual(deviceLocker.lockCount, 3)
    }

    func testOpenLidResetsLockRequest() {
        let clamshellStateReader = FakeLockClamshellStateReader(state: .closed)
        let deviceLocker = FakeDeviceLocker()
        let coordinator = ClosedLidLockCoordinator(
            clamshellStateReader: clamshellStateReader,
            deviceLocker: deviceLocker
        )
        var settings = UserSettings.defaults
        settings.lockScreenWhenLidCloses = true

        for _ in 0..<3 {
            _ = coordinator.update(settings: settings)
        }
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
        let clamshellStateReader = FakeLockClamshellStateReader(state: .closed)
        let deviceLocker = FakeDeviceLocker()
        deviceLocker.error = NSError(domain: "ScreenLock", code: 1)
        let coordinator = ClosedLidLockCoordinator(
            clamshellStateReader: clamshellStateReader,
            deviceLocker: deviceLocker
        )
        var settings = UserSettings.defaults
        settings.lockScreenWhenLidCloses = true

        let action = coordinator.update(settings: settings)

        guard case let .failed(message) = action else {
            XCTFail("Expected screen lock failure")
            return
        }
        XCTAssertTrue(message.contains("ScreenLock"))
        XCTAssertEqual(deviceLocker.lockCount, 1)
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
