import AppKit

/// Performs the process-wide activation changes that `ActivationPolicyController` decides on.
@MainActor
protocol ActivationPolicyApplying: AnyObject {
    /// Gives the app a Dock icon and pulls it in front of whatever app is currently frontmost.
    func activateAsForegroundApp()

    /// Returns the app to a menu bar only process with no Dock icon.
    func resignForegroundApp()
}

@MainActor
final class NSApplicationActivationPolicyApplier: ActivationPolicyApplying {
    func activateAsForegroundApp() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.unhide(nil)
        // `activate()` is cooperative and routinely refuses to take focus away from
        // the frontmost app, which leaves our window on screen but unfocused, so the
        // deprecated variant is the only one that reliably works for a utility the
        // user just asked to show something.
        application.activate(ignoringOtherApps: true)
    }

    func resignForegroundApp() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

/// The single owner of the app's activation policy.
///
/// Lid Awake normally runs as an `.accessory` process: no Dock icon, no app switcher
/// entry, and windows that never take keyboard focus. Anything that puts a window on
/// screen has to switch the process to `.regular` first and switch it back once the
/// window is gone. Several of them can be on screen at the same time, so the requests
/// are tracked as a set of reasons and the process only returns to `.accessory` once
/// the last reason has been released.
@MainActor
final class ActivationPolicyController {
    enum Reason: Hashable {
        case settingsWindow
        case permissionPrompt
        case updateSession
    }

    static let shared = ActivationPolicyController(applier: NSApplicationActivationPolicyApplier())

    private let applier: ActivationPolicyApplying
    private var activeReasons: Set<Reason> = []

    init(applier: ActivationPolicyApplying) {
        self.applier = applier
    }

    var foregroundReasons: Set<Reason> {
        activeReasons
    }

    /// Brings the app to the front and keeps it there until `endForeground(_:)` is
    /// called with the same reason.
    func beginForeground(_ reason: Reason) {
        activeReasons.insert(reason)
        applier.activateAsForegroundApp()
    }

    /// Releases a reason. Calling it for a reason that is not held does nothing, so
    /// callers with more than one end signal do not have to coordinate.
    func endForeground(_ reason: Reason) {
        guard activeReasons.remove(reason) != nil, activeReasons.isEmpty else {
            return
        }

        applier.resignForegroundApp()
    }
}
