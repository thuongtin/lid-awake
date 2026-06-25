import LidAwakeCore
import XCTest

final class WakePolicyCoordinatorTests: XCTestCase {
    func testStartsHoldingForManualSession() {
        let clock = FakeClock()
        let power = FakePowerController()
        let coordinator = WakePolicyCoordinator(powerController: power, clock: clock)

        let status = coordinator.update(
            settings: .defaults,
            sessions: [session()],
            battery: BatteryState(percent: 80, isCharging: false, isOnACPower: false, isLowPowerModeEnabled: false)
        )

        XCTAssertTrue(power.isHolding)
        XCTAssertEqual(power.acquireCount, 1)
        XCTAssertFalse(power.lastPreventDisplaySleep)
        XCTAssertEqual(status, .holding(WakeHoldReason(
            activeSessionIDs: ["session-1"],
            activeAgentNames: ["Codex CLI"],
            startedAt: clock.now,
            note: "Manual hold is active"
        )))
    }

    func testKeepDisplayOnModeRequestsDisplayAssertion() {
        let clock = FakeClock()
        let power = FakePowerController()
        let coordinator = WakePolicyCoordinator(powerController: power, clock: clock)
        var settings = UserSettings.defaults
        settings.lidClosedDisplayMode = .keepDisplayOn

        _ = coordinator.update(
            settings: settings,
            sessions: [session()],
            battery: BatteryState(percent: 80, isCharging: false, isOnACPower: true, isLowPowerModeEnabled: false)
        )

        XCTAssertTrue(power.lastPreventDisplaySleep)
    }

    func testDoesNotReleaseBeforeIdleDelay() {
        let clock = FakeClock()
        let power = FakePowerController()
        let coordinator = WakePolicyCoordinator(powerController: power, clock: clock)

        _ = coordinator.update(
            settings: .defaults,
            sessions: [session()],
            battery: BatteryState(percent: 80, isCharging: false, isOnACPower: false, isLowPowerModeEnabled: false)
        )

        clock.advance(seconds: 5)
        let status = coordinator.update(
            settings: .defaults,
            sessions: [session(state: .idle)],
            battery: BatteryState(percent: 80, isCharging: false, isOnACPower: false, isLowPowerModeEnabled: false)
        )

        XCTAssertTrue(power.isHolding)
        XCTAssertEqual(power.releaseCount, 0)
        if case .holding = status {
            return
        }
        XCTFail("Expected holding during idle grace period")
    }

    func testReleasesAfterIdleDelay() {
        let clock = FakeClock()
        let power = FakePowerController()
        let coordinator = WakePolicyCoordinator(powerController: power, clock: clock)

        _ = coordinator.update(
            settings: .defaults,
            sessions: [session()],
            battery: BatteryState(percent: 80, isCharging: false, isOnACPower: false, isLowPowerModeEnabled: false)
        )

        clock.advance(seconds: 5)
        _ = coordinator.update(
            settings: .defaults,
            sessions: [session(state: .idle)],
            battery: BatteryState(percent: 80, isCharging: false, isOnACPower: false, isLowPowerModeEnabled: false)
        )

        clock.advance(seconds: 30)
        let status = coordinator.update(
            settings: .defaults,
            sessions: [session(state: .idle)],
            battery: BatteryState(percent: 80, isCharging: false, isOnACPower: false, isLowPowerModeEnabled: false)
        )

        XCTAssertFalse(power.isHolding)
        XCTAssertEqual(power.releaseCount, 1)
        XCTAssertEqual(status, .watching)
    }

    func testPauseReleasesAndSuppressesHold() {
        let clock = FakeClock()
        let power = FakePowerController()
        let coordinator = WakePolicyCoordinator(powerController: power, clock: clock)
        var settings = UserSettings.defaults

        _ = coordinator.update(
            settings: settings,
            sessions: [session()],
            battery: BatteryState(percent: 80, isCharging: false, isOnACPower: false, isLowPowerModeEnabled: false)
        )

        let pauseUntil = clock.now.addingTimeInterval(60)
        settings.pauseUntil = pauseUntil
        let status = coordinator.update(
            settings: settings,
            sessions: [session()],
            battery: BatteryState(percent: 80, isCharging: false, isOnACPower: false, isLowPowerModeEnabled: false)
        )

        XCTAssertFalse(power.isHolding)
        XCTAssertEqual(status, .paused(until: pauseUntil))
    }

    func testBatteryCutoffReleasesImmediately() {
        let clock = FakeClock()
        let power = FakePowerController()
        let coordinator = WakePolicyCoordinator(powerController: power, clock: clock)

        _ = coordinator.update(
            settings: .defaults,
            sessions: [session()],
            battery: BatteryState(percent: 80, isCharging: false, isOnACPower: false, isLowPowerModeEnabled: false)
        )

        let status = coordinator.update(
            settings: .defaults,
            sessions: [session()],
            battery: BatteryState(percent: 20, isCharging: false, isOnACPower: false, isLowPowerModeEnabled: false)
        )

        XCTAssertFalse(power.isHolding)
        XCTAssertEqual(status, .blocked(.batteryCutoff(percent: 20, cutoff: 20)))
    }

    func testAllWorkingSessionsMustFinishBeforeReleaseDelayStarts() {
        let clock = FakeClock()
        let power = FakePowerController()
        let coordinator = WakePolicyCoordinator(powerController: power, clock: clock)

        _ = coordinator.update(
            settings: .defaults,
            sessions: [
                session(id: "a", kind: .codexCli, state: .working),
                session(id: "b", kind: .gemini, state: .working)
            ],
            battery: BatteryState(percent: 80, isCharging: false, isOnACPower: false, isLowPowerModeEnabled: false)
        )

        clock.advance(seconds: 60)
        let status = coordinator.update(
            settings: .defaults,
            sessions: [
                session(id: "a", kind: .codexCli, state: .idle),
                session(id: "b", kind: .gemini, state: .working)
            ],
            battery: BatteryState(percent: 80, isCharging: false, isOnACPower: false, isLowPowerModeEnabled: false)
        )

        XCTAssertTrue(power.isHolding)
        XCTAssertEqual(power.releaseCount, 0)
        if case let .holding(reason) = status {
            XCTAssertEqual(reason.activeSessionIDs, ["b"])
        } else {
            XCTFail("Expected holding for remaining working session")
        }
    }
}
