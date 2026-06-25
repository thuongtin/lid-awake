import Foundation

public enum AgentState: String, Codable, Hashable, Sendable {
    case working
    case idle
    case finished
    case unknown
}

public enum ActivitySource: String, Codable, Hashable, Sendable {
    case lifecycleHook
    case processDetection
}

public struct AgentSession: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: AgentKind
    public var displayName: String
    public var state: AgentState
    public var source: ActivitySource
    public var lastEventAt: Date
    public var processIdentifier: Int32?

    public init(
        id: String,
        kind: AgentKind,
        displayName: String,
        state: AgentState,
        source: ActivitySource,
        lastEventAt: Date,
        processIdentifier: Int32? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.state = state
        self.source = source
        self.lastEventAt = lastEventAt
        self.processIdentifier = processIdentifier
    }
}
