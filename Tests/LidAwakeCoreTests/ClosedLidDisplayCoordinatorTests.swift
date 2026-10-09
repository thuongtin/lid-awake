import LidAwakeCore
import XCTest

final class ClosedLidDisplayCoordinatorTests: XCTestCase {
    func testDoesNotRequestDisplaySleepWhenFirstObservedStateIsAlreadyClosed() {
        let clamshellStateReader = FakeClamshellStateReader(state: .closed)
        let displaySleeper = FakeDisplaySleeper()
        let coordinator = ClosedLidDisplayCoordinator(
            clamshellStateReader: clamshellStateReader,
            displaySleeper: displaySleeper
        )
        var settings = UserSettings.defaults
        settings.lidClosedDisplayMode = .turnDisplayOff

        let firstAction = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )
        let secondAction = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )

        XCTAssertEqual(firstAction, .none)
        XCTAssertEqual(secondAction, .none)
        XCTAssertEqual(displaySleeper.sleepCount, 0)
    }

    func testRequestsDisplaySleepWhenLidTransitionsToClosed() {
        let clamshellStateReader = FakeClamshellStateReader(state: .open)
        let displaySleeper = FakeDisplaySleeper()
        let coordinator = ClosedLidDisplayCoordinator(
            clamshellStateReader: clamshellStateReader,
            displaySleeper: displaySleeper
        )
        var settings = UserSettings.defaults
        settings.lidClosedDisplayMode = .turnDisplayOff

        let initialAction = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )
        clamshellStateReader.state = .closed
        let closeAction = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )

        XCTAssertEqual(initialAction, .none)
        XCTAssertEqual(closeAction, .requestedDisplaySleep)
        XCTAssertEqual(displaySleeper.sleepCount, 1)
    }

    func testDoesNotRequestDisplaySleepWhenStateMovesFromUnavailableToClosed() {
        let clamshellStateReader = FakeClamshellStateReader(state: .unavailable)
        let displaySleeper = FakeDisplaySleeper()
        let coordinator = ClosedLidDisplayCoordinator(
            clamshellStateReader: clamshellStateReader,
            displaySleeper: displaySleeper
        )
        var settings = UserSettings.defaults
        settings.lidClosedDisplayMode = .turnDisplayOff

        let initialAction = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )
        clamshellStateReader.state = .closed
        let closeAction = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )

        XCTAssertEqual(initialAction, .none)
        XCTAssertEqual(closeAction, .none)
        XCTAssertEqual(displaySleeper.sleepCount, 0)
    }

    func testRetriesDisplaySleepDuringClosedLidTransitionThenStops() {
        let clamshellStateReader = FakeClamshellStateReader(state: .open)
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
        clamshellStateReader.state = .closed
        let firstAction = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )
        let secondAction = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )
        let thirdAction = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )
        let fourthAction = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )

        XCTAssertEqual(firstAction, .requestedDisplaySleep)
        XCTAssertEqual(secondAction, .requestedDisplaySleep)
        XCTAssertEqual(thirdAction, .requestedDisplaySleep)
        XCTAssertEqual(fourthAction, .none)
        XCTAssertEqual(displaySleeper.sleepCount, 3)
    }

    func testARequestFoldedIntoOneStillRunningIsNotCounted() {
        let clamshellStateReader = FakeClamshellStateReader(state: .open)
        let displaySleeper = FakeDisplaySleeper()
        let coordinator = ClosedLidDisplayCoordinator(
            clamshellStateReader: clamshellStateReader,
            displaySleeper: displaySleeper
        )
        var settings = UserSettings.defaults
        settings.lidClosedDisplayMode = .turnDisplayOff

        _ = coordinator.update(settings: settings, wakeStatus: holdingStatus(), closedLidStatus: .enabled)
        clamshellStateReader.state = .closed

        // One slow command spans several ticks; only commands that actually
        // started use up the three attempts.
        var actions: [ClosedLidDisplayAction] = []
        for accepted in [true, false, false, false, true, true, true] {
            displaySleeper.acceptsRequest = accepted
            actions.append(coordinator.update(settings: settings, wakeStatus: holdingStatus(), closedLidStatus: .enabled))
        }

        XCTAssertEqual(actions, [
            .requestedDisplaySleep, .none, .none, .none,
            .requestedDisplaySleep, .requestedDisplaySleep, .none,
        ])
    }

    func testWaitsForLockedSessionBeforeDisplaySleepWhenLockOnCloseIsEnabled() {
        let clamshellStateReader = FakeClamshellStateReader(state: .open)
        let displaySleeper = FakeDisplaySleeper()
        let screenLockStateReader = FakeScreenLockStateReader(state: .unlocked)
        let coordinator = ClosedLidDisplayCoordinator(
            clamshellStateReader: clamshellStateReader,
            displaySleeper: displaySleeper,
            screenLockStateReader: screenLockStateReader
        )
        var settings = UserSettings.defaults
        settings.lidClosedDisplayMode = .turnDisplayOff
        settings.lockScreenWhenLidCloses = true

        _ = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )
        clamshellStateReader.state = .closed
        let firstAction = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )
        let secondAction = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )
        screenLockStateReader.state = .locked
        let thirdAction = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )

        XCTAssertEqual(firstAction, .none)
        XCTAssertEqual(secondAction, .none)
        XCTAssertEqual(thirdAction, .requestedDisplaySleep)
        XCTAssertEqual(displaySleeper.sleepCount, 1)
    }

    func testRequestsDisplaySleepWhenScreenLockStateIsUnavailable() {
        let clamshellStateReader = FakeClamshellStateReader(state: .open)
        let displaySleeper = FakeDisplaySleeper()
        let screenLockStateReader = FakeScreenLockStateReader(state: .unavailable)
        let coordinator = ClosedLidDisplayCoordinator(
            clamshellStateReader: clamshellStateReader,
            displaySleeper: displaySleeper,
            screenLockStateReader: screenLockStateReader
        )
        var settings = UserSettings.defaults
        settings.lidClosedDisplayMode = .turnDisplayOff
        settings.lockScreenWhenLidCloses = true

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
        XCTAssertEqual(displaySleeper.sleepCount, 1)
    }

    func testRequestsDisplaySleepWhenScreenLockWaitIsBypassed() {
        let clamshellStateReader = FakeClamshellStateReader(state: .open)
        let displaySleeper = FakeDisplaySleeper()
        let screenLockStateReader = FakeScreenLockStateReader(state: .unlocked)
        let coordinator = ClosedLidDisplayCoordinator(
            clamshellStateReader: clamshellStateReader,
            displaySleeper: displaySleeper,
            screenLockStateReader: screenLockStateReader
        )
        var settings = UserSettings.defaults
        settings.lidClosedDisplayMode = .turnDisplayOff
        settings.lockScreenWhenLidCloses = true

        _ = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )
        clamshellStateReader.state = .closed
        let action = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled,
            waitForScreenLockBeforeDisplaySleep: false
        )

        XCTAssertEqual(action, .requestedDisplaySleep)
        XCTAssertEqual(displaySleeper.sleepCount, 1)
    }

    func testOpenLidResetsDisplaySleepRequest() {
        let clamshellStateReader = FakeClamshellStateReader(state: .open)
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
        clamshellStateReader.state = .closed
        for _ in 0..<3 {
            _ = coordinator.update(
                settings: settings,
                wakeStatus: holdingStatus(),
                closedLidStatus: .enabled
            )
        }
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
        XCTAssertEqual(displaySleeper.sleepCount, 4)
    }

    func testDoesNotRequestDisplaySleepWhenKeepingDisplayOnDuringClosure() {
        let clamshellStateReader = FakeClamshellStateReader(state: .open)
        let displaySleeper = FakeDisplaySleeper()
        let coordinator = ClosedLidDisplayCoordinator(
            clamshellStateReader: clamshellStateReader,
            displaySleeper: displaySleeper
        )
        var settings = UserSettings.defaults
        settings.lidClosedDisplayMode = .keepDisplayOn

        _ = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )
        clamshellStateReader.state = .closed
        let closeAction = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )
        settings.lidClosedDisplayMode = .turnDisplayOff
        let changedWhileClosedAction = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )

        XCTAssertEqual(closeAction, .none)
        XCTAssertEqual(changedWhileClosedAction, .none)
        XCTAssertEqual(displaySleeper.sleepCount, 0)
    }

    func testWaitsForClosedLidModeAfterObservedTransition() {
        let clamshellStateReader = FakeClamshellStateReader(state: .open)
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
            closedLidStatus: .disabled
        )
        clamshellStateReader.state = .closed
        let waitingAction = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .disabled
        )
        let enabledAction = coordinator.update(
            settings: settings,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )

        XCTAssertEqual(waitingAction, .none)
        XCTAssertEqual(enabledAction, .requestedDisplaySleep)
        XCTAssertEqual(displaySleeper.sleepCount, 1)
    }

    func testLidClosureIDChangesOnlyWhenAClosureStartsOrEnds() {
        let clamshellStateReader = FakeClamshellStateReader(state: .open)
        let coordinator = ClosedLidDisplayCoordinator(
            clamshellStateReader: clamshellStateReader,
            displaySleeper: FakeDisplaySleeper()
        )
        var settings = UserSettings.defaults
        settings.lidClosedDisplayMode = .turnDisplayOff
        let update = {
            coordinator.update(settings: settings, wakeStatus: holdingStatus(), closedLidStatus: .enabled)
        }

        update()
        let openID = coordinator.lidClosureID
        clamshellStateReader.state = .closed
        update()
        let closedID = coordinator.lidClosureID
        update()
        XCTAssertNotEqual(closedID, openID)
        XCTAssertEqual(coordinator.lidClosureID, closedID)

        clamshellStateReader.state = .open
        update()
        XCTAssertNotEqual(coordinator.lidClosureID, closedID)
        let reopenedID = coordinator.lidClosureID
        update()
        XCTAssertEqual(coordinator.lidClosureID, reopenedID)
    }

    func testReturnsFailureWhenDisplaySleepFails() {
        let clamshellStateReader = FakeClamshellStateReader(state: .open)
        let displaySleeper = FakeDisplaySleeper()
        displaySleeper.error = NSError(domain: "DisplaySleep", code: 1)
        let coordinator = ClosedLidDisplayCoordinator(
            clamshellStateReader: clamshellStateReader,
            displaySleeper: displaySleeper
        )

        _ = coordinator.update(
            settings: .defaults,
            wakeStatus: holdingStatus(),
            closedLidStatus: .enabled
        )
        clamshellStateReader.state = .closed
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

private final class FakeScreenLockStateReader: ScreenLockStateReading {
    var state: ScreenLockState

    init(state: ScreenLockState) {
        self.state = state
    }

    func screenLockState() -> ScreenLockState {
        state
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
    var acceptsRequest = true

    func sleepDisplaysNow() throws -> Bool {
        sleepCount += 1
        if let error {
            throw error
        }
        return acceptsRequest
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
