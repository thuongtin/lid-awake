import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private let activationPolicyController = ActivationPolicyController.shared
    private lazy var settingsWindowPresenter = SettingsWindowPresenter(
        model: model,
        activationPolicyController: activationPolicyController
    )
    private var statusItemController: StatusItemController?
    private let logger = Logger(subsystem: "com.thuongtin.LidAwake", category: "app")
    private var didPresentClosedLidPermissionPrompt = false
    private var isPreparingToTerminate = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("applicationDidFinishLaunching")
        NSApplication.shared.setActivationPolicy(.accessory)
        model.start()
        statusItemController = StatusItemController(model: model) { [weak self] in
            self?.openSettings()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.presentClosedLidPermissionPromptIfNeeded()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A second quit while the restore runs waits on the first one.
        guard !isPreparingToTerminate else {
            return .terminateLater
        }

        isPreparingToTerminate = true
        logger.info("applicationShouldTerminate")
        model.prepareForTermination {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("applicationWillTerminate")
        statusItemController?.invalidate()
        model.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshAfterExternalPermissionChange()
    }

    @objc func showSettings(_ sender: Any?) {
        openSettings()
    }

    func openSettings() {
        model.refreshAfterExternalPermissionChange()
        statusItemController?.closePopover()
        settingsWindowPresenter.show()
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
        activationPolicyController.beginForeground(.permissionPrompt)

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
            break
        }

        // Released after the settings window has claimed its own reason, so the app
        // never blinks back to `.accessory` in between.
        activationPolicyController.endForeground(.permissionPrompt)
    }
}
