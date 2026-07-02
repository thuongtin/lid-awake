import AppKit
import Combine
import LidAwakeCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let model: AppModel
    private let openSettings: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.popover = NSPopover()
        self.model = model
        self.openSettings = openSettings
        super.init()
        configureStatusItem()
        configurePopover()
        observeModel()
    }

    func closePopover() {
        popover.performClose(nil)
    }

    func invalidate() {
        closePopover()
        cancellables.removeAll()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
            return
        }

        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else {
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.toolTip = "Lid Awake"
        updateButton(for: model.status)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(model: model) { [weak self] in
                guard let self else {
                    return
                }

                closePopover()
                openSettings()
            }
        )
    }

    private func observeModel() {
        model.$status
            .sink { [weak self] status in
                Task { @MainActor in
                    self?.updateButton(for: status)
                }
            }
            .store(in: &cancellables)
    }

    private func updateButton(for status: WakeStatus) {
        guard let button = statusItem.button else {
            return
        }

        button.contentTintColor = nil
        button.image = statusImage(for: status)
    }

    private func statusImage(for status: WakeStatus) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)

        guard
            let baseImage = NSImage(
                systemSymbolName: symbolName(for: status),
                accessibilityDescription: accessibilityDescription(for: status)
            ),
            let image = baseImage.withSymbolConfiguration(configuration)
        else {
            return nil
        }

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    private func symbolName(for status: WakeStatus) -> String {
        switch status {
        case .holding:
            return "bolt.circle.fill"
        case .blocked:
            return "exclamationmark.triangle.fill"
        case .paused:
            return "pause.circle.fill"
        case .inactive:
            return "moon.circle.fill"
        case .watching:
            return "bolt.circle"
        }
    }

    private func accessibilityDescription(for status: WakeStatus) -> String {
        switch status {
        case .holding:
            return "Lid Awake is keeping the Mac awake"
        case .blocked:
            return "Lid Awake needs attention"
        case .paused:
            return "Lid Awake is paused"
        case .inactive:
            return "Lid Awake is off"
        case .watching:
            return "Lid Awake is ready"
        }
    }

}
