@testable import LidAwake
import XCTest

final class AppCommandRunnerTests: XCTestCase {
    func testReportsAnIdentifiedSigningTeam() {
        let output = """
        Executable=/Applications/LidAwake.app/Contents/MacOS/LidAwake
        Identifier=com.thuongtin.LidAwake
        TeamIdentifier=ABCDE12345
        Sealed Resources version=2 rules=13 files=4
        """

        XCTAssertEqual(
            AppCommandRunner.codeSigningReport(codesignOutput: output),
            ["teamIdentifier=ABCDE12345", "codeSigningMode=identified"]
        )
    }

    func testReportsAnAdHocSignature() {
        let output = """
        Identifier=com.thuongtin.LidAwake
        Signature=adhoc
        TeamIdentifier=not set
        """

        XCTAssertEqual(
            AppCommandRunner.codeSigningReport(codesignOutput: output),
            ["teamIdentifier=not set", "codeSigningMode=adhoc"]
        )
    }

    func testDoesNotCallASignatureIdentifiedWithoutATeamIdentifier() {
        XCTAssertEqual(
            AppCommandRunner.codeSigningReport(codesignOutput: "Identifier=com.thuongtin.LidAwake"),
            ["teamIdentifier=unknown", "codeSigningMode=unknown"]
        )
    }
}
