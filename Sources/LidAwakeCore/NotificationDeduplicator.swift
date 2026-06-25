import Foundation

public enum NotificationEvent: Hashable, Sendable {
    case holdEngaged
    case holdReleased
    case batteryCutoff
    case lowPowerBlocked
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
