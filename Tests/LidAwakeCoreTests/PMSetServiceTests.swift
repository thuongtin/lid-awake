import LidAwakeCore
import XCTest

final class PMSetServiceTests: XCTestCase {
    func testParsesCurrentSleepDisabledOutput() {
        let output = """
        System-wide power settings:
         SleepDisabled        1
         displaysleep         10
        """

        XCTAssertEqual(PMSetService.parseClosedLidStatus(from: output), .enabled)
    }

    func testParsesLegacyDisableSleepOutput() {
        let output = """
        Battery Power:
         disablesleep         0
         displaysleep         2
        """

        XCTAssertEqual(PMSetService.parseClosedLidStatus(from: output), .disabled)
    }

    func testReturnsNotReportedWhenClosedLidSettingIsMissing() {
        let output = """
        AC Power:
         sleep                1
         displaysleep         10
        """

        XCTAssertEqual(PMSetService.parseClosedLidStatus(from: output), .notReported)
    }

    func testDetectsRootPermissionFailureOutput() {
        XCTAssertTrue(PMSetService.isPermissionFailureOutput("'pmset' must be run as root..."))
    }

    func testDetectsOperationNotPermittedOutput() {
        XCTAssertTrue(PMSetService.isPermissionFailureOutput("The operation couldn't be completed. Operation not permitted"))
    }

    func testAllowsNormalEmptyOutput() {
        XCTAssertFalse(PMSetService.isPermissionFailureOutput(""))
    }
}
