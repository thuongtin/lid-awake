import LidAwakeCore
import Foundation
import UserNotifications

@MainActor
final class SystemNotificationService {
    private let deduplicator = NotificationDeduplicator(clock: SystemClock())
    private var permissionRequested = false

    func handleTransition(from oldStatus: WakeStatus, to newStatus: WakeStatus) {
        let event = notificationEvent(from: oldStatus, to: newStatus)
        guard let event, deduplicator.shouldSend(event) else {
            return
        }

        send(event)
    }

    private func notificationEvent(from oldStatus: WakeStatus, to newStatus: WakeStatus) -> NotificationEvent? {
        switch (oldStatus, newStatus) {
        case (_, .holding) where !oldStatus.isHolding:
            .holdEngaged
        case (.holding, .watching), (.holding, .inactive):
            .holdReleased
        case (_, .blocked(.batteryCutoff)):
            .batteryCutoff
        case (_, .blocked(.lowPowerMode)):
            .lowPowerBlocked
        default:
            nil
        }
    }

    private func send(_ event: NotificationEvent) {
        let center = UNUserNotificationCenter.current()
        if !permissionRequested {
            permissionRequested = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        let content = UNMutableNotificationContent()
        content.title = "Lid Awake"
        content.body = body(for: event)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "agentawake.\(event)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    private func body(for event: NotificationEvent) -> String {
        switch event {
        case .holdEngaged:
            "Keeping your Mac awake."
        case .holdReleased:
            "Wake assertions were released."
        case .batteryCutoff:
            "Battery cutoff reached. Wake assertions were released."
        case .lowPowerBlocked:
            "Low Power Mode is active. Wake assertions are blocked."
        }
    }
}

private extension WakeStatus {
    var isHolding: Bool {
        if case .holding = self {
            return true
        }
        return false
    }
}
