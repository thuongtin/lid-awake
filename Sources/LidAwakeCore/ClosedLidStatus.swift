import Foundation

public enum ClosedLidStatus: String, Codable, Equatable, Sendable {
    case enabled
    case disabled
    case notReported

    public var displayText: String {
        switch self {
        case .enabled:
            "Enabled"
        case .disabled:
            "Disabled"
        case .notReported:
            "Not reported"
        }
    }
}
