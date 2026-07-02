import LidAwakeCore
import XCTest

final class HelperCodeSigningRequirementTests: XCTestCase {
    func testReturnsExpectedStringWhenTeamIdentifierPresent() {
        let requirement = HelperCodeSigningRequirement.requirement(
            bundleIdentifier: "com.thuongtin.LidAwake",
            teamIdentifier: "ABCDE12345"
        )

        XCTAssertEqual(
            requirement,
            "identifier \"com.thuongtin.LidAwake\" and anchor apple generic and certificate leaf[subject.OU] = \"ABCDE12345\""
        )
    }

    func testReturnsNilWhenTeamIdentifierIsNil() {
        let requirement = HelperCodeSigningRequirement.requirement(
            bundleIdentifier: "com.thuongtin.LidAwake",
            teamIdentifier: nil
        )

        XCTAssertNil(requirement)
    }

    func testReturnsNilWhenTeamIdentifierIsEmpty() {
        let requirement = HelperCodeSigningRequirement.requirement(
            bundleIdentifier: "com.thuongtin.LidAwake",
            teamIdentifier: ""
        )

        XCTAssertNil(requirement)
    }

    func testReturnsNilWhenTeamIdentifierContainsQuoteOrSpace() {
        let requirement = HelperCodeSigningRequirement.requirement(
            bundleIdentifier: "com.thuongtin.LidAwake",
            teamIdentifier: "AB\"CD"
        )

        XCTAssertNil(requirement)
    }

    func testReturnsNilWhenBundleIdentifierContainsQuote() {
        let requirement = HelperCodeSigningRequirement.requirement(
            bundleIdentifier: "com.thuongtin\"LidAwake",
            teamIdentifier: "ABCDE12345"
        )

        XCTAssertNil(requirement)
    }
}
