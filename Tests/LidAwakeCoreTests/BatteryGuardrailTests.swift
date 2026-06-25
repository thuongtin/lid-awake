import LidAwakeCore
import XCTest

final class BatteryGuardrailTests: XCTestCase {
    func testLowBatteryBlocksHoldWhenDischarging() {
        let clock = FakeClock()
        let power = FakePowerController()
        let coordinator = WakePolicyCoordinator(powerController: power, clock: clock)

        let status = coordinator.update(
            settings: .defaults,
            sessions: [session()],
            battery: BatteryState(percent: 19, isCharging: false, isOnACPower: false, isLowPowerModeEnabled: false)
        )

        XCTAssertFalse(power.isHolding)
        XCTAssertEqual(status, .blocked(.batteryCutoff(percent: 19, cutoff: 20)))
    }

    func testChargingBelowThresholdCanHold() {
        let clock = FakeClock()
        let power = FakePowerController()
        let coordinator = WakePolicyCoordinator(powerController: power, clock: clock)

        _ = coordinator.update(
            settings: .defaults,
            sessions: [session()],
            battery: BatteryState(percent: 10, isCharging: true, isOnACPower: true, isLowPowerModeEnabled: false)
        )

        XCTAssertTrue(power.isHolding)
    }

    func testLowPowerModeBlocksByDefault() {
        let clock = FakeClock()
        let power = FakePowerController()
        let coordinator = WakePolicyCoordinator(powerController: power, clock: clock)

        let status = coordinator.update(
            settings: .defaults,
            sessions: [session()],
            battery: BatteryState(percent: 80, isCharging: false, isOnACPower: false, isLowPowerModeEnabled: true)
        )

        XCTAssertFalse(power.isHolding)
        XCTAssertEqual(status, .blocked(.lowPowerMode))
    }

    func testDesktopOrUnknownBatteryDoesNotBlock() {
        let clock = FakeClock()
        let power = FakePowerController()
        let coordinator = WakePolicyCoordinator(powerController: power, clock: clock)

        _ = coordinator.update(
            settings: .defaults,
            sessions: [session()],
            battery: .desktopOrUnknown(lowPowerMode: false)
        )

        XCTAssertTrue(power.isHolding)
    }

    func testOnlyWhenPluggedInBlocksBatteryPower() {
        let clock = FakeClock()
        let power = FakePowerController()
        let coordinator = WakePolicyCoordinator(powerController: power, clock: clock)
        var settings = UserSettings.defaults
        settings.onlyWhenPluggedIn = true

        let status = coordinator.update(
            settings: settings,
            sessions: [session()],
            battery: BatteryState(percent: 80, isCharging: false, isOnACPower: false, isLowPowerModeEnabled: false)
        )

        XCTAssertFalse(power.isHolding)
        XCTAssertEqual(status, .blocked(.notPluggedIn))
    }
}
