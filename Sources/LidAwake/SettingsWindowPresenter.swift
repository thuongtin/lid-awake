import AppKit
import SwiftUI

@MainActor
final class SettingsWindowPresenter: NSObject, NSWindowDelegate {
    private weak var model: AppModel?
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        guard let model else {
            return
        }

        let settingsWindow = window(for: model)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.unhide(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private func window(for model: AppModel) -> NSWindow {
        if let window {
            return window
        }

        let hostingController = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 820, height: 560))
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        self.window = window
        return window
    }
}
