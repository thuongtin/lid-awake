import AppKit
import SwiftUI

@MainActor
final class SettingsWindowPresenter: NSObject, NSWindowDelegate {
    private weak var model: AppModel?
    private let activationPolicyController: ActivationPolicyController
    private var window: NSWindow?

    init(model: AppModel, activationPolicyController: ActivationPolicyController) {
        self.model = model
        self.activationPolicyController = activationPolicyController
    }

    func show() {
        guard let model else {
            return
        }

        let settingsWindow = window(for: model)
        activationPolicyController.beginForeground(.settingsWindow)
        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        activationPolicyController.endForeground(.settingsWindow)
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
