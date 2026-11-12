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
        XCTAssertNil(settings.stopAt)
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

    func testLegacyPauseDeadlineIsNotTakenForAStopDeadline() throws {
        // A pause meant "stay off until then", the opposite of a stop deadline,
        // and an expired one would otherwise turn the app off after an update.
        for legacyDeadline in [Date(timeIntervalSince1970: 1_000_000_000), Date(timeIntervalSince1970: 4_000_000_000)] {
            let data = Data("""
            {
              "enabled": true,
              "pauseUntil": \(legacyDeadline.timeIntervalSinceReferenceDate)
            }
            """.utf8)

            let settings = try JSONDecoder().decode(UserSettings.self, from: data)

            XCTAssertNil(settings.stopAt)
            XCTAssertTrue(settings.enabled)
        }
    }

    func testEncodesOnlyStopDeadline() throws {
        let settings = UserSettings(stopAt: Date(timeIntervalSince1970: 1_800_000_000))
        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(object["stopAt"])
        XCTAssertNil(object["pauseUntil"])
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
