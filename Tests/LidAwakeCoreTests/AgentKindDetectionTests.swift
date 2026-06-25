import LidAwakeCore
import XCTest

final class AgentKindDetectionTests: XCTestCase {
    func testDetectsKnownAgentsFromProcessNames() {
        XCTAssertEqual(AgentKind.detect(processName: "/usr/local/bin/codex"), .codexCli)
        XCTAssertEqual(AgentKind.detect(processName: "Claude"), .claudeCode)
        XCTAssertEqual(AgentKind.detect(processName: "opencode"), .openCode)
        XCTAssertEqual(AgentKind.detect(processName: "gemini"), .gemini)
        XCTAssertEqual(AgentKind.detect(processName: "Cursor"), .cursor)
        XCTAssertEqual(AgentKind.detect(processName: "Cline"), .cline)
    }

    func testUnknownProcessReturnsNil() {
        XCTAssertNil(AgentKind.detect(processName: "Safari"))
    }
}
