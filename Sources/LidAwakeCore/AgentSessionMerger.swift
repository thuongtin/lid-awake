import Foundation

public enum AgentSessionMerger {
    public static func merge(
        hookSessions: [AgentSession],
        processSessions: [AgentSession]
    ) -> [AgentSession] {
        var sessionsByID: [String: AgentSession] = [:]

        for session in processSessions {
            sessionsByID[session.id] = session
        }

        for session in hookSessions {
            sessionsByID[session.id] = session
        }

        return sessionsByID.values.sorted { lhs, rhs in
            if lhs.state != rhs.state {
                return lhs.state.sortOrder < rhs.state.sortOrder
            }
            if lhs.displayName != rhs.displayName {
                return lhs.displayName < rhs.displayName
            }
            return lhs.id < rhs.id
        }
    }
}

private extension AgentState {
    var sortOrder: Int {
        switch self {
        case .working:
            0
        case .idle:
            1
        case .finished:
            2
        case .unknown:
            3
        }
    }
}
