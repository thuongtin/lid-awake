import Foundation

public enum AgentKind: String, CaseIterable, Codable, Hashable, Sendable {
    case claudeCode = "claude_code"
    case codexCli = "codex_cli"
    case openCode = "opencode"
    case gemini
    case cursor
    case cline
    case unknown

    public var displayName: String {
        switch self {
        case .claudeCode:
            "Claude Code"
        case .codexCli:
            "Codex CLI"
        case .openCode:
            "OpenCode"
        case .gemini:
            "Gemini"
        case .cursor:
            "Cursor"
        case .cline:
            "Cline"
        case .unknown:
            "Unknown"
        }
    }

    public static func detect(processName: String, bundleIdentifier: String? = nil) -> AgentKind? {
        let process = processName.lowercased()
        let bundle = bundleIdentifier?.lowercased() ?? ""

        if process.contains("claude") || bundle.contains("claude") {
            return .claudeCode
        }

        if process == "codex" || process.contains("/codex") || bundle.contains("codex") {
            return .codexCli
        }

        if process.contains("opencode") || bundle.contains("opencode") {
            return .openCode
        }

        if process.contains("gemini") || bundle.contains("gemini") {
            return .gemini
        }

        if process.contains("cursor") || bundle.contains("cursor") {
            return .cursor
        }

        if process.contains("cline") || bundle.contains("cline") {
            return .cline
        }

        return nil
    }
}
