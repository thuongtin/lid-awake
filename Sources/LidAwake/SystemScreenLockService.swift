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
        // `AppModel` asks for Accessibility once per launch. Prompting here
        // would queue a system dialog on every closed-lid lock attempt.
        guard Self.hasAccessibilityPermission(prompt: false) else {
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

/// Locks the screen without holding the caller on a lock command.
///
/// The command path runs on `blockingWork` and reports a failure later
/// through `failureHandler`. The keyboard shortcut path only posts events, so
/// it stays synchronous and still throws when Accessibility is missing.
final class SystemScreenLockService: DeviceLocking {
    static let commandTimeout: TimeInterval = 2

    var failureHandler: (@MainActor (String) -> Void)?

    private let shortcutPoster: ScreenLockShortcutPosting
    private let resolveMethod: () -> ScreenLockMethod
    private let blockingWork: BlockingWorkPerforming
    private let runCommand: (ScreenLockCommand) -> ProcessResult
    /// Touched only on the main actor, where requests start and finish.
    private var isRunning = false

    init(
        shortcutPoster: ScreenLockShortcutPosting = CGEventScreenLockShortcutPoster(),
        resolveMethod: @escaping () -> ScreenLockMethod = { ScreenLockCommandResolver.resolve() },
        blockingWork: BlockingWorkPerforming = BackgroundBlockingWork(label: "com.thuongtin.LidAwake.screen-lock"),
        runCommand: @escaping (ScreenLockCommand) -> ProcessResult = { command in
            ProcessRunner.run(
                command.executablePath,
                arguments: command.arguments,
                timeout: SystemScreenLockService.commandTimeout
            )
        }
    ) {
        self.shortcutPoster = shortcutPoster
        self.resolveMethod = resolveMethod
        self.blockingWork = blockingWork
        self.runCommand = runCommand
    }

    func lockScreenNow() throws {
        switch resolveMethod() {
        case let .command(command):
            run(command)
        case .keyboardShortcut:
            try shortcutPoster.postLockScreenShortcut()
        }
    }

    private func run(_ command: ScreenLockCommand) {
        guard !isRunning else {
            return
        }

        isRunning = true
        let runCommand = runCommand
        blockingWork.perform({
            runCommand(command)
        }, then: { [weak self] result in
            guard let self else {
                return
            }

            isRunning = false
            guard result.timedOut || result.status != 0 else {
                return
            }

            let error: ScreenLockError = result.timedOut
                ? .commandFailed(result.status, "The screen lock command did not finish in time.")
                : .commandFailed(result.status, result.output)
            failureHandler?(error.localizedDescription)
        })
    }
}
