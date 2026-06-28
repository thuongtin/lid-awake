import LidAwakeCore
import XCTest

final class HelperClientAuthorizerTests: XCTestCase {
    func testAcceptsExpectedAppIdentifier() {
        let provider = FakeCodeSigningInfoProvider(result: .success(CodeSigningInfo(
            signingIdentifier: LidAwakeHelperConstants.clientBundleIdentifier,
            bundleIdentifier: nil,
            teamIdentifier: "TEAM12345"
        )))
        let authorizer = HelperClientAuthorizer(allowedTeamIdentifier: "TEAM12345", provider: provider)

        XCTAssertTrue(authorizer.isAuthorized(processID: 42))
    }

    func testAcceptsExpectedBundleIdentifierWhenTeamMatches() {
        let provider = FakeCodeSigningInfoProvider(result: .success(CodeSigningInfo(
            signingIdentifier: nil,
            bundleIdentifier: LidAwakeHelperConstants.clientBundleIdentifier,
            teamIdentifier: "TEAM12345"
        )))
        let authorizer = HelperClientAuthorizer(allowedTeamIdentifier: "TEAM12345", provider: provider)

        XCTAssertTrue(authorizer.isAuthorized(processID: 42))
    }

    func testRejectsWrongIdentifier() {
        let provider = FakeCodeSigningInfoProvider(result: .success(CodeSigningInfo(
            signingIdentifier: "com.example.OtherApp",
            bundleIdentifier: "com.example.OtherApp",
            teamIdentifier: "TEAM12345"
        )))
        let authorizer = HelperClientAuthorizer(allowedTeamIdentifier: "TEAM12345", provider: provider)

        XCTAssertFalse(authorizer.isAuthorized(processID: 42))
    }

    func testRejectsMissingIdentifier() {
        let provider = FakeCodeSigningInfoProvider(result: .success(CodeSigningInfo(
            signingIdentifier: nil,
            bundleIdentifier: nil,
            teamIdentifier: "TEAM12345"
        )))
        let authorizer = HelperClientAuthorizer(allowedTeamIdentifier: "TEAM12345", provider: provider)

        XCTAssertFalse(authorizer.isAuthorized(processID: 42))
    }

    func testRejectsWrongTeamIdentifier() {
        let provider = FakeCodeSigningInfoProvider(result: .success(CodeSigningInfo(
            signingIdentifier: LidAwakeHelperConstants.clientBundleIdentifier,
            bundleIdentifier: nil,
            teamIdentifier: "OTHERTEAM"
        )))
        let authorizer = HelperClientAuthorizer(allowedTeamIdentifier: "TEAM12345", provider: provider)

        XCTAssertFalse(authorizer.isAuthorized(processID: 42))
    }

    func testRejectsMissingClientTeamIdentifier() {
        let provider = FakeCodeSigningInfoProvider(result: .success(CodeSigningInfo(
            signingIdentifier: LidAwakeHelperConstants.clientBundleIdentifier,
            bundleIdentifier: nil,
            teamIdentifier: nil
        )))
        let authorizer = HelperClientAuthorizer(allowedTeamIdentifier: "TEAM12345", provider: provider)

        XCTAssertFalse(authorizer.isAuthorized(processID: 42))
    }

    func testRejectsWhenHelperTeamIdentifierIsUnavailable() {
        let provider = FakeCodeSigningInfoProvider(
            result: .success(CodeSigningInfo(
                signingIdentifier: LidAwakeHelperConstants.clientBundleIdentifier,
                bundleIdentifier: nil,
                teamIdentifier: "TEAM12345"
            )),
            currentProcessResult: .success(CodeSigningInfo(
                signingIdentifier: LidAwakeHelperConstants.machServiceName,
                bundleIdentifier: nil,
                teamIdentifier: nil
            ))
        )
        let authorizer = HelperClientAuthorizer(provider: provider)

        XCTAssertFalse(authorizer.isAuthorized(processID: 42))
    }

    func testRejectsProviderFailure() {
        let provider = FakeCodeSigningInfoProvider(result: .failure(FakeCodeSigningInfoError.failed))
        let authorizer = HelperClientAuthorizer(allowedTeamIdentifier: "TEAM12345", provider: provider)

        XCTAssertFalse(authorizer.isAuthorized(processID: 42))
    }
}

private final class FakeCodeSigningInfoProvider: CodeSigningInfoProviding {
    private let result: Result<CodeSigningInfo, Error>
    private let currentProcessResult: Result<CodeSigningInfo, Error>

    init(
        result: Result<CodeSigningInfo, Error>,
        currentProcessResult: Result<CodeSigningInfo, Error> = .success(CodeSigningInfo(
            signingIdentifier: LidAwakeHelperConstants.machServiceName,
            bundleIdentifier: nil,
            teamIdentifier: "TEAM12345"
        ))
    ) {
        self.result = result
        self.currentProcessResult = currentProcessResult
    }

    func codeSigningInfo(forProcessID processID: pid_t) throws -> CodeSigningInfo {
        try result.get()
    }

    func currentProcessCodeSigningInfo() throws -> CodeSigningInfo {
        try currentProcessResult.get()
    }
}

private enum FakeCodeSigningInfoError: Error {
    case failed
}
