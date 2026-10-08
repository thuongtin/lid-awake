import LidAwakeCore
import ApplicationServices
import AppKit
import Foundation

enum ScreenLockError: LocalizedError, Equatable {
    case unavailable
    case accessibilityPermissionRequired
    case commandFailed(Int32, String)

    static let accessibilityPermissionMessage =
        "Allow the current Lid Awake app in System Settings > Privacy & Security > Accessibility to lock the screen."

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "No supported macOS screen lock command is available."
        case .accessibilityPermissionRequired:
            Self.accessibilityPermissionMessage
        case let .commandFailed(status, output):
            output.isEmpty ? "screen lock failed with exit code \(status)." : output
        }
    }
}

struct ScreenLockCommand: Equatable {
    let executablePath: String
    let arguments: [String]
}

enum ScreenLockMethod: Equatable {
    case command(ScreenLockCommand)
    case keyboardShortcut
}

enum ScreenLockCommandResolver {
    static let cgSessionPath = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"

    static func resolve(
        isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) -> ScreenLockMethod {
        if isExecutable(cgSessionPath) {
            return .command(
                ScreenLockCommand(
                    executablePath: cgSessionPath,
                    arguments: ["-suspend"]
                )
            )
        }

        return .keyboardShortcut
    }
}

protocol ScreenLockShortcutPosting {
    func postLockScreenShortcut() throws
}

final class CGEventScreenLockShortcutPoster: ScreenLockShortcutPosting {
    private let lockScreenKeyCode: CGKeyCode = 12

    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func postLockScreenShortcut() throws {
        guard Self.hasAccessibilityPermission(prompt: true) else {
            throw ScreenLockError.accessibilityPermissionRequired
        }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: lockScreenKeyCode,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: lockScreenKeyCode,
                keyDown: false
              ) else {
            throw ScreenLockError.unavailable
        }

        let flags: CGEventFlags = [.maskCommand, .maskControl]
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

protocol ScreenLockPermissionChecking {
    var requiresAccessibilityPermission: Bool { get }
    func hasAccessibilityPermission(prompt: Bool) -> Bool
    func openAccessibilitySettings()
}

struct SystemScreenLockPermissionChecker: ScreenLockPermissionChecking {
    var requiresAccessibilityPermission: Bool {
        ScreenLockCommandResolver.resolve() == .keyboardShortcut
    }

    func hasAccessibilityPermission(prompt: Bool) -> Bool {
        CGEventScreenLockShortcutPoster.hasAccessibilityPermission(prompt: prompt)
    }

    func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security"
        ]

        for value in urls {
            guard let url = URL(string: value), NSWorkspace.shared.open(url) else {
                continue
            }
            return
        }
    }
}

final class SystemScreenLockService: DeviceLocking {
    /// Runs from the main actor's side-effects timer, so a hung lock command
    /// must not be able to hold it.
    static let commandTimeout: TimeInterval = 2

    private let shortcutPoster: ScreenLockShortcutPosting

    init(shortcutPoster: ScreenLockShortcutPosting = CGEventScreenLockShortcutPoster()) {
        self.shortcutPoster = shortcutPoster
    }

    func lockScreenNow() throws {
        switch ScreenLockCommandResolver.resolve() {
        case let .command(command):
            try run(command)
        case .keyboardShortcut:
            try shortcutPoster.postLockScreenShortcut()
        }
    }

    private func run(_ command: ScreenLockCommand) throws {
        let result = ProcessRunner.run(
            command.executablePath,
            arguments: command.arguments,
            timeout: Self.commandTimeout
        )
        guard !result.timedOut, result.status == 0 else {
            throw ScreenLockError.commandFailed(result.status, result.output)
        }
    }
}
