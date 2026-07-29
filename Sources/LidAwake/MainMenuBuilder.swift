import AppKit

/// Builds the standard macOS main menu that SwiftUI's `App` scene graph used to
/// provide implicitly. The app menu's "Settings…" item is wired directly to
/// `AppDelegate.openSettings()` so that every entry point (menu, Cmd+comma,
/// status-item popover) opens the one real settings window.
enum MainMenuBuilder {
    static func makeMainMenu(settingsTarget: AppDelegate) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem(settingsTarget: settingsTarget))
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(windowMenuItem())
        return mainMenu
    }

    private static var appName: String {
        let info = Bundle.main.infoDictionary
        let name = info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
        guard let name, !name.isEmpty else {
            return ProcessInfo.processInfo.processName
        }

        return name
    }

    private static func appMenuItem(settingsTarget: AppDelegate) -> NSMenuItem {
        let name = appName
        let menu = NSMenu(title: name)

        menu.addItem(
            item(
                title: "About \(name)",
                action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())

        let settingsItem = item(
            title: "Settings…",
            action: #selector(AppDelegate.showSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = settingsTarget
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let servicesItem = item(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        NSApplication.shared.servicesMenu = servicesMenu
        menu.addItem(servicesItem)
        menu.addItem(.separator())

        menu.addItem(
            item(title: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        )

        let hideOthers = item(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)

        menu.addItem(
            item(
                title: "Show All",
                action: #selector(NSApplication.unhideAllApplications(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())

        menu.addItem(
            item(title: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )

        let container = NSMenuItem()
        container.submenu = menu
        return container
    }

    private static func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")

        menu.addItem(item(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))

        let redo = item(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())

        menu.addItem(item(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(item(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(item(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))

        let pasteMatchingStyle = item(
            title: "Paste and Match Style",
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "v"
        )
        pasteMatchingStyle.keyEquivalentModifierMask = [.command, .option, .shift]
        menu.addItem(pasteMatchingStyle)

        menu.addItem(item(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        menu.addItem(
            item(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        )

        let container = NSMenuItem()
        container.submenu = menu
        return container
    }

    private static func windowMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Window")

        menu.addItem(
            item(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        )
        menu.addItem(item(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        menu.addItem(
            item(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        )
        menu.addItem(.separator())
        menu.addItem(
            item(
                title: "Bring All to Front",
                action: #selector(NSApplication.arrangeInFront(_:)),
                keyEquivalent: ""
            )
        )

        NSApplication.shared.windowsMenu = menu

        let container = NSMenuItem()
        container.submenu = menu
        return container
    }

    private static func item(title: String, action: Selector?, keyEquivalent: String) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    }
}
