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
