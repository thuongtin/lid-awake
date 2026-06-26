import LidAwakeCore
import XCTest

final class UserSettingsTests: XCTestCase {
    func testDefaultsAreSafe() {
        let settings = UserSettings.defaults

        XCTAssertTrue(settings.enabled)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(settings.batteryCutoffPercent, 20)
        XCTAssertFalse(settings.onlyWhenPluggedIn)
        XCTAssertTrue(settings.respectLowPowerMode)
        XCTAssertEqual(settings.idleReleaseDelaySeconds, 30)
        XCTAssertTrue(settings.preventDisplaySleep)
        XCTAssertEqual(settings.lidClosedDisplayMode, .turnDisplayOff)
        XCTAssertFalse(settings.lockScreenWhenLidCloses)
        XCTAssertFalse(settings.shouldPreventDisplaySleep)
        XCTAssertTrue(settings.shouldPreventClosedLidSleep)
        XCTAssertNil(settings.pauseUntil)
    }

    func testDecodesLegacySettingsWithNewDefaults() throws {
        let data = Data("""
        {
          "enabled": true,
          "batteryCutoffPercent": 15,
          "onlyWhenPluggedIn": true,
          "respectLowPowerMode": true,
          "idleReleaseDelaySeconds": 45,
          "preventDisplaySleep": true
        }
        """.utf8)

        let settings = try JSONDecoder().decode(UserSettings.self, from: data)

        XCTAssertTrue(settings.enabled)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(settings.batteryCutoffPercent, 15)
        XCTAssertEqual(settings.lidClosedDisplayMode, .turnDisplayOff)
        XCTAssertFalse(settings.lockScreenWhenLidCloses)
    }

    func testDisplaySleepAssertionRequiresKeepDisplayOnMode() {
        var settings = UserSettings.defaults
        settings.preventDisplaySleep = true
        settings.lidClosedDisplayMode = .turnDisplayOff
        XCTAssertFalse(settings.shouldPreventDisplaySleep)
        XCTAssertTrue(settings.shouldPreventClosedLidSleep)

        settings.lidClosedDisplayMode = .keepDisplayOn
        XCTAssertTrue(settings.shouldPreventDisplaySleep)
        XCTAssertTrue(settings.shouldPreventClosedLidSleep)
    }
}
