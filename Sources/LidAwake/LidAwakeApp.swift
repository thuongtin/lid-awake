import AppKit
import OSLog
import SwiftUI

@main
struct LidAwakeApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                model: appDelegate.model,
                openSettings: {
                    appDelegate.openSettings()
                }
            )
        } label: {
            Label("Lid Awake", systemImage: "bolt.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private lazy var settingsWindowPresenter = SettingsWindowPresenter(model: model)
    private let logger = Logger(subsystem: "com.thuongtin.LidAwake", category: "app")
    private var didPresentClosedLidPermissionPrompt = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("applicationDidFinishLaunching")
        NSApplication.shared.setActivationPolicy(.accessory)
        model.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.presentClosedLidPermissionPromptIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("applicationWillTerminate")
        model.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshAfterExternalPermissionChange()
    }

    @objc func openSettings() {
        model.refreshAfterExternalPermissionChange()
        dismissMenuBarExtraWindows()
        settingsWindowPresenter.show()
        DispatchQueue.main.async { [weak self] in
            self?.dismissMenuBarExtraWindows()
        }
    }

    private func dismissMenuBarExtraWindows() {
        for window in NSApplication.shared.windows where window.isVisible && window.title != "Settings" {
            window.orderOut(nil)
        }
    }

    private func presentClosedLidPermissionPromptIfNeeded() {
        guard !didPresentClosedLidPermissionPrompt else {
            return
        }

        model.refreshClosedLidPermissionState()
        guard model.shouldShowClosedLidPermissionPrompt else {
            return
        }

        didPresentClosedLidPermissionPrompt = true
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = model.closedLidAttentionTitle
        alert.informativeText = model.closedLidAttentionMessage
        alert.addButton(withTitle: model.closedLidPrimaryActionTitle)
        alert.addButton(withTitle: "Open Lid Awake Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            model.requestClosedLidPermission()
            openSettings()
        case .alertSecondButtonReturn:
            openSettings()
        default:
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}
