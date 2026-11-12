import LidAwakeCore
import XCTest

final class ProcessRunnerTests: XCTestCase {
    func testCapturesStandardOutputAndStandardError() {
        let result = ProcessRunner.run(
            "/bin/sh",
            arguments: ["-c", "echo out; echo err >&2; exit 3"],
            timeout: 5
        )

        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(result.output, "out\nerr")
    }

    func testDrainsOutputLargerThanThePipeBuffer() {
        // A child that fills a pipe blocks on write until someone reads it, so
        // reading only after exit would deadlock here.
        let result = ProcessRunner.run(
            "/bin/sh",
            arguments: ["-c", "yes lid | head -c 300000"],
            timeout: 5
        )

        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.status, 0)
        XCTAssertGreaterThan(result.output.count, 250_000)
    }

    func testTerminatesAProcessThatOutlivesItsTimeout() {
        let startedAt = Date()

        let result = ProcessRunner.run("/bin/sleep", arguments: ["30"], timeout: 0.2)

        XCTAssertTrue(result.timedOut)
        XCTAssertNotEqual(result.status, 0)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 3)
    }

    func testReportsALaunchFailure() {
        let result = ProcessRunner.run("/nonexistent/lid-awake-test", arguments: [], timeout: 5)

        XCTAssertFalse(result.timedOut)
        XCTAssertNotEqual(result.status, 0)
        XCTAssertFalse(result.output.isEmpty)
    }
}
