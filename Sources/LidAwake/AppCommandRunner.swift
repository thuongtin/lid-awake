import AppKit
import LidAwakeCore

private struct HelperRepairWhileAppRunsError: LocalizedError {
    var errorDescription: String? {
        "Lid Awake is running. Quit it first, or repair the helper from Lid Awake Settings."
    }
}

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
                // A repair stops the helper's restore watchdog, and a running
                // app would never learn that it needs to arm the new one.
                guard !isAnotherCopyRunning() else {
                    throw HelperRepairWhileAppRunsError()
                }
                try repairRegistration(helperService: helperService)
                print(helperService.status.displayText)
            case "--helper-remove":
                try ClosedLidHelperRemoval.removeHelper(
                    helperService: helperService,
                    statusReader: PMSetService(),
                    ownershipStore: UserDefaultsClosedLidOwnershipStore(),
                    appIsRunning: isAnotherCopyRunning()
                )
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

    private static func repairRegistration(helperService: ClosedLidHelperService) throws {
        var result: Result<Void, Error>?
        helperService.repairRegistration { outcome in
            DispatchQueue.main.async {
                result = outcome
            }
        }
        while result == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        try result?.get()
    }

    private static func isAnotherCopyRunning() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { $0.processIdentifier != currentProcessID }
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
        printCodeSigningStatus()
    }

    private static func printCodeSigningStatus() {
        let process = Process()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", Bundle.main.bundlePath]
        process.standardError = stderr
        process.standardOutput = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("codeSigningStatus=unavailable")
            print("codeSigningError=\(error.localizedDescription)")
            return
        }

        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let teamIdentifier = firstCodesignValue(named: "TeamIdentifier", in: output) ?? "unknown"
        print("teamIdentifier=\(teamIdentifier)")
        print("codeSigningMode=\(teamIdentifier == "not set" ? "adhoc" : "identified")")
    }

    private static func firstCodesignValue(named key: String, in output: String) -> String? {
        for line in output.split(separator: "\n") {
            let prefix = "\(key)="
            guard line.hasPrefix(prefix) else {
                continue
            }
            return String(line.dropFirst(prefix.count))
        }

        return nil
    }
}
