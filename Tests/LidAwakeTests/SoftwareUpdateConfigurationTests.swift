@testable import LidAwake
import XCTest

final class SoftwareUpdateConfigurationTests: XCTestCase {
    func testBothValuesPresentIsConfiguredWithReadyMessage() {
        let configuration = SoftwareUpdateConfiguration(
            feedURL: "https://example.com/appcast.xml",
            publicKey: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLM123="
        )

        XCTAssertTrue(configuration.isConfigured)
        XCTAssertEqual(configuration.message, "Ready to check for signed updates.")
    }

    func testMissingFeedURLIsNotConfigured() {
        let configuration = SoftwareUpdateConfiguration(
            feedURL: nil,
            publicKey: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLM123="
        )

        XCTAssertFalse(configuration.isConfigured)
        XCTAssertEqual(configuration.message, "This build does not include a Sparkle feed URL.")
    }

    func testMissingPublicKeyIsNotConfigured() {
        let configuration = SoftwareUpdateConfiguration(
            feedURL: "https://example.com/appcast.xml",
            publicKey: nil
        )

        XCTAssertFalse(configuration.isConfigured)
        XCTAssertEqual(configuration.message, "This build does not include a Sparkle update signing key.")
    }

    func testBothMissingIsNotConfigured() {
        let configuration = SoftwareUpdateConfiguration(feedURL: nil, publicKey: nil)

        XCTAssertFalse(configuration.isConfigured)
        XCTAssertEqual(
            configuration.message,
            "This build does not include a Sparkle feed URL or update signing key."
        )
    }

    func testWhitespaceOnlyValuesAreTreatedAsMissing() {
        let configuration = SoftwareUpdateConfiguration(feedURL: "  \n", publicKey: "  \n")

        XCTAssertFalse(configuration.isConfigured)
        XCTAssertEqual(
            configuration.message,
            "This build does not include a Sparkle feed URL or update signing key."
        )
    }
}
