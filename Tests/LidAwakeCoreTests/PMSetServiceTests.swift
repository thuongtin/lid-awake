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

    func testStatusReadGivesUpAfterATimedOutPMSet() {
        let runner = RecordingProcessRunner(result: ProcessResult(status: -1, output: "", timedOut: true))
        let service = PMSetService(runProcess: runner.run)

        XCTAssertEqual(service.readClosedLidStatus(), .notReported)
        // A hung pmset would hang again, so the fallback read is skipped.
        XCTAssertEqual(runner.calls.map(\.arguments), [["-g"]])
        XCTAssertEqual(runner.calls.first?.timeout, PMSetService.statusReadTimeout)
    }

    func testStatusReadFallsBackToCustomSettings() {
        let runner = RecordingProcessRunner(results: [
            ProcessResult(status: 0, output: "System-wide power settings:", timedOut: false),
            ProcessResult(status: 0, output: "AC Power:\n disablesleep 1", timedOut: false)
        ])
        let service = PMSetService(runProcess: runner.run)

        XCTAssertEqual(service.readClosedLidStatus(), .enabled)
        XCTAssertEqual(runner.calls.map(\.arguments), [["-g"], ["-g", "custom"]])
    }

    func testClosedLidChangeFailsWhenPMSetTimesOut() {
        let runner = RecordingProcessRunner(result: ProcessResult(status: -1, output: "pmset hung", timedOut: true))
        let service = PMSetService(runProcess: runner.run)

        XCTAssertThrowsError(try service.setClosedLidMode(enabled: false)) { error in
            XCTAssertEqual(error as? PMSetError, .timedOut("pmset hung"))
        }
        XCTAssertEqual(runner.calls.map(\.arguments), [["-a", "disablesleep", "0"]])
        XCTAssertEqual(runner.calls.first?.timeout, PMSetService.closedLidChangeTimeout)
    }
}

private final class RecordingProcessRunner: @unchecked Sendable {
    struct Call {
        let executable: String
        let arguments: [String]
        let timeout: TimeInterval
    }

    private let lock = NSLock()
    private var results: [ProcessResult]
    private var recordedCalls: [Call] = []

    init(result: ProcessResult) {
        self.results = [result]
    }

    init(results: [ProcessResult]) {
        self.results = results
    }

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> ProcessResult {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append(Call(executable: executable, arguments: arguments, timeout: timeout))
        return results.count > 1 ? results.removeFirst() : results[0]
    }
}
