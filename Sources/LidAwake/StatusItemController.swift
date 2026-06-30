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

        button.image = NSImage(
            systemSymbolName: "bolt.circle",
            accessibilityDescription: "Lid Awake"
        )
        button.imagePosition = .imageOnly
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
        statusItem.button?.contentTintColor = tint(for: status)
    }

    private func tint(for status: WakeStatus) -> NSColor {
        switch status {
        case .holding:
            return .systemGreen
        case .blocked:
            return .systemOrange
        case .paused:
            return .systemYellow
        case .inactive:
            return .secondaryLabelColor
        case .watching:
            return .systemBlue
        }
    }
}
