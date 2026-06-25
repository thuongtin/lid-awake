import LidAwakeCore
import XCTest

final class AgentSessionMergerTests: XCTestCase {
    func testHookSessionsOverrideSameIDProcessSessions() {
        let process = AgentSession(
            id: "same",
            kind: .codexCli,
            displayName: "Codex CLI",
            state: .working,
            source: .processDetection,
            lastEventAt: Date()
        )
        let hook = AgentSession(
            id: "same",
            kind: .codexCli,
            displayName: "Codex CLI",
            state: .idle,
            source: .lifecycleHook,
            lastEventAt: Date()
        )

        let merged = AgentSessionMerger.merge(
            hookSessions: [hook],
            processSessions: [process]
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].state, .idle)
        XCTAssertEqual(merged[0].source, .lifecycleHook)
    }

    func testWorkingSessionsSortFirst() {
        let merged = AgentSessionMerger.merge(
            hookSessions: [
                session(id: "idle", kind: .gemini, state: .idle),
                session(id: "working", kind: .codexCli, state: .working)
            ],
            processSessions: []
        )

        XCTAssertEqual(merged.map(\.id), ["working", "idle"])
    }
}
