import LidAwakeCore
import XCTest

final class AgentHookEventTests: XCTestCase {
    func testWorkingEventCreatesSession() throws {
        let event = try AgentHookEventParser.parseLine("""
        {"schemaVersion":1,"agentKind":"codex_cli","sessionId":"abc","state":"working","timestamp":"2026-06-24T10:00:00Z","cwd":"/tmp/project"}
        """)
        var store = AgentSessionStore()

        store.apply(event: event)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].id, "abc")
        XCTAssertEqual(store.sessions[0].kind, .codexCli)
        XCTAssertEqual(store.sessions[0].state, .working)
        XCTAssertEqual(store.sessions[0].source, .lifecycleHook)
    }

    func testIdleEventUpdatesSession() throws {
        var store = AgentSessionStore()
        let working = try AgentHookEventParser.parseLine("""
        {"schemaVersion":1,"agentKind":"codex_cli","sessionId":"abc","state":"working","timestamp":"2026-06-24T10:00:00Z"}
        """)
        let idle = try AgentHookEventParser.parseLine("""
        {"schemaVersion":1,"agentKind":"codex_cli","sessionId":"abc","state":"idle","timestamp":"2026-06-24T10:01:00Z"}
        """)

        store.apply(event: working)
        store.apply(event: idle)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].state, .idle)
    }

    func testMalformedJSONIsRejected() {
        XCTAssertThrowsError(try AgentHookEventParser.parseLine("{bad json"))
    }

    func testUnknownStateIsRejected() {
        XCTAssertThrowsError(try AgentHookEventParser.parseLine("""
        {"schemaVersion":1,"agentKind":"codex_cli","sessionId":"abc","state":"unknown","timestamp":"2026-06-24T10:00:00Z"}
        """)) { error in
            XCTAssertEqual(error as? AgentHookEventParseError, .unknownState)
        }
    }

    func testUnsupportedSchemaIsRejected() {
        XCTAssertThrowsError(try AgentHookEventParser.parseLine("""
        {"schemaVersion":2,"agentKind":"codex_cli","sessionId":"abc","state":"working","timestamp":"2026-06-24T10:00:00Z"}
        """)) { error in
            XCTAssertEqual(error as? AgentHookEventParseError, .unsupportedSchemaVersion(2))
        }
    }
}
