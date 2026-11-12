import LidAwakeCore
import Foundation
import UserNotifications

@MainActor
final class SystemNotificationService {
    private let deduplicator = NotificationDeduplicator(clock: SystemClock())
    private var permissionRequested = false

    func handleTransition(from oldStatus: WakeStatus, to newStatus: WakeStatus) {
        let event = NotificationEvent.forTransition(from: oldStatus, to: newStatus)
        guard let event, deduplicator.shouldSend(event) else {
            return
        }

        send(event)
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
            identifier: "lidawake.\(event)",
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
