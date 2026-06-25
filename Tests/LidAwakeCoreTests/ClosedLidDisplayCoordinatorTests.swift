import LidAwakeCore
import XCTest

final class ClosedLidDisplayCoordinatorTests: XCTestCase {
    func testRequestsDisplaySleepWhenClosedLidModeTurnsDisplayOff() {
        let clamshellStateReader = FakeClamshellStateReader(state: .closed)
        let displaySleeper = FakeDisplaySleeper()
        let coordinator = ClosedLidDisplayCoordinator(
            clamshellStateReader: clamshellStateReader,
            displaySleeper: displaySleeper
        )
        var settings = UserSettings.defaults
        settings.lidClosedDisplayMode = .turnDisplayOff

        let action = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )

        XCTAssertEqual(action, .requestedDisplaySleep)
        XCTAssertEqual(displaySleeper.sleepCount, 1)
    }

    func testRequestsDisplaySleepOnlyOnceForSameClosure() {
        let clamshellStateReader = FakeClamshellStateReader(state: .closed)
        let displaySleeper = FakeDisplaySleeper()
        let coordinator = ClosedLidDisplayCoordinator(
            clamshellStateReader: clamshellStateReader,
            displaySleeper: displaySleeper
        )
        var settings = UserSettings.defaults
        settings.lidClosedDisplayMode = .turnDisplayOff

        _ = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )
        let action = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )

        XCTAssertEqual(action, .none)
        XCTAssertEqual(displaySleeper.sleepCount, 1)
    }

    func testOpenLidResetsDisplaySleepRequest() {
        let clamshellStateReader = FakeClamshellStateReader(state: .closed)
        let displaySleeper = FakeDisplaySleeper()
        let coordinator = ClosedLidDisplayCoordinator(
            clamshellStateReader: clamshellStateReader,
            displaySleeper: displaySleeper
        )
        var settings = UserSettings.defaults
        settings.lidClosedDisplayMode = .turnDisplayOff

        _ = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )
        clamshellStateReader.state = .open
        _ = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )
        clamshellStateReader.state = .closed
        let action = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )

        XCTAssertEqual(action, .requestedDisplaySleep)
        XCTAssertEqual(displaySleeper.sleepCount, 2)
    }

    func testDoesNotRequestDisplaySleepWhenKeepingDisplayOn() {
        let clamshellStateReader = FakeClamshellStateReader(state: .closed)
        let displaySleeper = FakeDisplaySleeper()
        let coordinator = ClosedLidDisplayCoordinator(
            clamshellStateReader: clamshellStateReader,
            displaySleeper: displaySleeper
        )
        var settings = UserSettings.defaults
        settings.lidClosedDisplayMode = .keepDisplayOn

        let action = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )

        XCTAssertEqual(action, .none)
        XCTAssertEqual(displaySleeper.sleepCount, 0)
    }

    func testDoesNotRequestDisplaySleepBeforeClosedLidModeIsEnabled() {
        let clamshellStateReader = FakeClamshellStateReader(state: .closed)
        let displaySleeper = FakeDisplaySleeper()
        let coordinator = ClosedLidDisplayCoordinator(
            clamshellStateReader: clamshellStateReader,
            displaySleeper: displaySleeper
        )

        let action = coordinator.update(
            settings: .defaults,
            wakeStatus: holdingStatus(),
            closedLidStatus: .disabled
        )

        XCTAssertEqual(action, .none)
        XCTAssertEqual(displaySleeper.sleepCount, 0)
    }

    func testReturnsFailureWhenDisplaySleepFails() {
        let clamshellStateReader = FakeClamshellStateReader(state: .closed)
        let displaySleeper = FakeDisplaySleeper()
        displaySleeper.error = NSError(domain: "DisplaySleep", code: 1)
        let coordinator = ClosedLidDisplayCoordinator(
            clamshellStateReader: clamshellStateReader,
            displaySleeper: displaySleeper
        )

        let action = coordinator.update(
            settings: .defaults,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )

        guard case let .failed(message) = action else {
            XCTFail("Expected display sleep failure")
            return
        }
        XCTAssertTrue(message.contains("DisplaySleep"))
        XCTAssertEqual(displaySleeper.sleepCount, 1)
    }
}

private final class FakeClamshellStateReader: ClamshellStateReading {
    var state: ClamshellState

    init(state: ClamshellState) {
        self.state = state
    }

    func clamshellState() -> ClamshellState {
        state
    }
}

private final class FakeDisplaySleeper: DisplaySleeping {
    var sleepCount = 0
    var error: Error?

    func sleepDisplaysNow() throws {
        sleepCount += 1
        if let error {
            throw error
        }
    }
}

private func holdingStatus() -> WakeStatus {
    .holding(WakeHoldReason(
        activeSessionIDs: ["manual-hold"],
        activeAgentNames: ["Manual Hold"],
        startedAt: Date(timeIntervalSince1970: 1_800_000_000),
        note: "test"
    ))
}
