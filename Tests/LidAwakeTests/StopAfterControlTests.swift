@testable import LidAwake
import XCTest

final class StopAfterControlTests: XCTestCase {
    func testTypedMinutesAreReadAsTheyAreTyped() {
        XCTAssertEqual(StopAfterControl.minutes(fromTyped: "45"), 45)
        XCTAssertEqual(StopAfterControl.minutes(fromTyped: " 90 "), 90)
        XCTAssertEqual(StopAfterControl.minutes(fromTyped: "1,000"), 720)
        XCTAssertEqual(StopAfterControl.minutes(fromTyped: "0"), 1)
    }

    func testUnreadableTextIsIgnored() {
        XCTAssertNil(StopAfterControl.minutes(fromTyped: ""))
        XCTAssertNil(StopAfterControl.minutes(fromTyped: "abc"))
    }
}
