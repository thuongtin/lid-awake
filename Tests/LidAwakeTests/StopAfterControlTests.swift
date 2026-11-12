@testable import LidAwake
import XCTest

final class StopAfterControlTests: XCTestCase {
    func testTypedMinutesAreReadAsTheyAreTyped() {
        XCTAssertEqual(StopAfterControl.minutes(fromTyped: "45"), 45)
        XCTAssertEqual(StopAfterControl.minutes(fromTyped: " 90 "), 90)
        XCTAssertEqual(StopAfterControl.minutes(fromTyped: "1,000"), 720)
        XCTAssertEqual(StopAfterControl.minutes(fromTyped: "0"), 1)
    }

    func testDigitsFromOtherScriptsAreRead() {
        // Arabic-Indic and fullwidth digits, which `Int(_:)` cannot parse.
        XCTAssertEqual(StopAfterControl.minutes(fromTyped: "\u{0663}\u{0660}"), 30)
        XCTAssertEqual(StopAfterControl.minutes(fromTyped: "\u{FF14}\u{FF15}"), 45)
        XCTAssertEqual(StopAfterControl.minutes(fromTyped: "99999999999999999999999"), 720)
    }

    func testUnreadableTextIsIgnored() {
        XCTAssertNil(StopAfterControl.minutes(fromTyped: ""))
        XCTAssertNil(StopAfterControl.minutes(fromTyped: "abc"))
        // A whole number, but not a single digit.
        XCTAssertNil(StopAfterControl.minutes(fromTyped: "\u{4E07}"))
    }
}
