import Foundation

public enum AgentHookEventParseError: Error, Equatable {
    case emptyLine
    case unsupportedSchemaVersion(Int)
    case unknownState
}

public struct AgentHookEvent: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var agentKind: AgentKind
    public var sessionId: String
    public var state: AgentState
    public var timestamp: Date
    public var cwd: String?

    public init(
        schemaVersion: Int,
        agentKind: AgentKind,
        sessionId: String,
        state: AgentState,
        timestamp: Date,
        cwd: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.agentKind = agentKind
        self.sessionId = sessionId
        self.state = state
        self.timestamp = timestamp
        self.cwd = cwd
    }
}

public enum AgentHookEventParser {
    public static func parseLine(_ line: String) throws -> AgentHookEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentHookEventParseError.emptyLine
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(AgentHookEvent.self, from: Data(trimmed.utf8))

        guard event.schemaVersion == 1 else {
            throw AgentHookEventParseError.unsupportedSchemaVersion(event.schemaVersion)
        }

        guard event.state != .unknown else {
            throw AgentHookEventParseError.unknownState
        }

        return event
    }
}

public struct AgentSessionStore: Sendable {
    private var sessionsByID: [String: AgentSession] = [:]

    public init() {}

    public var sessions: [AgentSession] {
        sessionsByID.values.sorted { lhs, rhs in
            lhs.lastEventAt > rhs.lastEventAt
        }
    }

    public mutating func apply(event: AgentHookEvent) {
        sessionsByID[event.sessionId] = AgentSession(
            id: event.sessionId,
            kind: event.agentKind,
            displayName: event.agentKind.displayName,
            state: event.state,
            source: .lifecycleHook,
            lastEventAt: event.timestamp
        )
    }
}
