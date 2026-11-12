import Foundation

public enum NotificationEvent: Hashable, Sendable {
    case holdEngaged
    case holdReleased
    case batteryCutoff
    case lowPowerBlocked
}

public extension NotificationEvent {
    /// The notification a status change deserves, if any.
    ///
    /// The caller passes every evaluate through here, changed or not, and a
    /// battery cutoff carries the current percent, so a block notifies only
    /// when the app moves into that kind of block, not on every reading.
    static func forTransition(from oldStatus: WakeStatus, to newStatus: WakeStatus) -> NotificationEvent? {
        switch (oldStatus, newStatus) {
        case (.holding, .holding):
            return nil
        case (_, .holding):
            return .holdEngaged
        case (.blocked(.batteryCutoff), .blocked(.batteryCutoff)):
            return nil
        case (_, .blocked(.batteryCutoff)):
            return .batteryCutoff
        case (.blocked(.lowPowerMode), .blocked(.lowPowerMode)):
            return nil
        case (_, .blocked(.lowPowerMode)):
            return .lowPowerBlocked
        case (.holding, _):
            // Every other way out of a hold, so that a release with no
            // notification of its own, such as unplugging the power adapter,
            // is not silent after the hold itself was announced.
            return .holdReleased
        default:
            return nil
        }
    }
}

public final class NotificationDeduplicator {
    private let clock: Clock
    private let window: TimeInterval
    private var lastSentAt: [NotificationEvent: Date] = [:]

    public init(clock: Clock, window: TimeInterval = 600) {
        self.clock = clock
        self.window = window
    }

    public func shouldSend(_ event: NotificationEvent) -> Bool {
        let now = clock.now
        if let last = lastSentAt[event], now.timeIntervalSince(last) < window {
            return false
        }

        lastSentAt[event] = now
        return true
    }
}
