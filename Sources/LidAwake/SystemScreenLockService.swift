import LidAwakeCore
import ApplicationServices
import AppKit
import Foundation

enum ScreenLockError: LocalizedError, Equatable {
    case unavailable
    case accessibilityPermissionRequired
    case launchFailed(String)
    case commandFailed(Int32, String)

    static let accessibilityPermissionMessage =
        "Allow the current Lid Awake app in System Settings > Privacy & Security > Accessibility to lock the screen."

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "No supported macOS screen lock command is available."
        case .accessibilityPermissionRequired:
            Self.accessibilityPermissionMessage
        case let .launchFailed(message):
            message
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
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = command.arguments
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ScreenLockError.launchFailed(error.localizedDescription)
        }

        let output = read(stdout) + read(stderr)
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw ScreenLockError.commandFailed(process.terminationStatus, trimmedOutput)
        }
    }

    private func read(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
