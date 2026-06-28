import Foundation

enum AppCommandRunner {
    static func runIfNeeded(arguments: [String] = CommandLine.arguments) {
        guard let command = arguments.dropFirst().first(where: { argument in
            argument.hasPrefix("--helper-") || argument.hasPrefix("--screen-lock-")
        }) else {
            return
        }

        do {
            let helperService = ClosedLidHelperService()
            switch command {
            case "--helper-repair":
                try helperService.repairRegistration()
                print(helperService.status.displayText)
            case "--helper-remove":
                try helperService.unregister()
                print(helperService.status.displayText)
            case "--helper-status":
                print(helperService.status.displayText)
            case "--screen-lock-status":
                printScreenLockStatus()
            default:
                fputs("Unknown command: \(command)\n", stderr)
                exit(2)
            }
            exit(0)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func printScreenLockStatus() {
        let method = ScreenLockCommandResolver.resolve()
        switch method {
        case let .command(command):
            print("screenLockMethod=command")
            print("screenLockCommand=\(command.executablePath)")
        case .keyboardShortcut:
            let trusted = CGEventScreenLockShortcutPoster.hasAccessibilityPermission(prompt: false)
            print("screenLockMethod=keyboardShortcut")
            print("accessibilityTrusted=\(trusted)")
        }
        print("bundleIdentifier=\(Bundle.main.bundleIdentifier ?? "unknown")")
        print("bundlePath=\(Bundle.main.bundlePath)")
    }
}
