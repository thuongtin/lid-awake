import LidAwakeCore
import XCTest

final class HelperClientAuthorizerTests: XCTestCase {
    func testAcceptsExpectedAppIdentifier() {
        let provider = FakeCodeSigningInfoProvider(result: .success(CodeSigningInfo(
            signingIdentifier: LidAwakeHelperConstants.clientBundleIdentifier,
            bundleIdentifier: nil
        )))
        let authorizer = HelperClientAuthorizer(provider: provider)

        XCTAssertTrue(authorizer.isAuthorized(processID: 42))
    }

    func testRejectsWrongIdentifier() {
        let provider = FakeCodeSigningInfoProvider(result: .success(CodeSigningInfo(
            signingIdentifier: "com.example.OtherApp",
            bundleIdentifier: "com.example.OtherApp"
        )))
        let authorizer = HelperClientAuthorizer(provider: provider)

        XCTAssertFalse(authorizer.isAuthorized(processID: 42))
    }

    func testRejectsMissingIdentifier() {
        let provider = FakeCodeSigningInfoProvider(result: .success(CodeSigningInfo(
            signingIdentifier: nil,
            bundleIdentifier: nil
        )))
        let authorizer = HelperClientAuthorizer(provider: provider)

        XCTAssertFalse(authorizer.isAuthorized(processID: 42))
    }

    func testRejectsProviderFailure() {
        let provider = FakeCodeSigningInfoProvider(result: .failure(FakeCodeSigningInfoError.failed))
        let authorizer = HelperClientAuthorizer(provider: provider)

        XCTAssertFalse(authorizer.isAuthorized(processID: 42))
    }
}

private final class FakeCodeSigningInfoProvider: CodeSigningInfoProviding {
    private let result: Result<CodeSigningInfo, Error>

    init(result: Result<CodeSigningInfo, Error>) {
        self.result = result
    }

    func codeSigningInfo(forProcessID processID: pid_t) throws -> CodeSigningInfo {
        try result.get()
    }
}

private enum FakeCodeSigningInfoError: Error {
    case failed
}
