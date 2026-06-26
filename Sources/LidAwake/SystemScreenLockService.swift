import LidAwakeCore
import Foundation

enum ScreenLockError: LocalizedError, Equatable {
    case unavailable
    case launchFailed(String)
    case commandFailed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "No supported macOS screen lock command is available."
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

enum ScreenLockCommandResolver {
    static let cgSessionPath = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
    static let openPath = "/usr/bin/open"
    static let screenSaverAppPath = "/System/Library/CoreServices/ScreenSaverEngine.app"

    static func resolve(
        isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:),
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) -> ScreenLockCommand? {
        if isExecutable(cgSessionPath) {
            return ScreenLockCommand(
                executablePath: cgSessionPath,
                arguments: ["-suspend"]
            )
        }

        if isExecutable(openPath), fileExists(screenSaverAppPath) {
            return ScreenLockCommand(
                executablePath: openPath,
                arguments: [screenSaverAppPath]
            )
        }

        return nil
    }
}

final class SystemScreenLockService: DeviceLocking {
    func lockScreenNow() throws {
        guard let command = ScreenLockCommandResolver.resolve() else {
            throw ScreenLockError.unavailable
        }

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
