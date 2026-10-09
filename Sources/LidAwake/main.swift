import AppKit
import OSLog

// Helper and diagnostic subcommands print to stdout and exit, so they must run
// before any AppKit state is created.
AppCommandRunner.runIfNeeded()

// Held for the life of the process. A command-line helper change holds it
// exclusively, so wait for one in progress rather than send the helper changes
// it cannot see. Each command answers within its own timeouts.
let appInstanceLock: AppInstanceLock? = {
    switch AppInstanceLock.acquire(.shared, waitingUpTo: 30) {
    case let .acquired(lock):
        return lock
    case .busy:
        Logger(subsystem: "com.thuongtin.LidAwake", category: "app")
            .error("a command-line helper change still holds the app instance lock, starting anyway")
        return nil
    case let .unavailable(message):
        Logger(subsystem: "com.thuongtin.LidAwake", category: "app")
            .error("could not take the app instance lock error=\(message, privacy: .public)")
        return nil
    }
}()

// Top-level code is not main-actor isolated under the Swift 5 language mode, but
// it does run on the main thread, so this assumption holds.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    // `run()` never returns, so this binding keeps the delegate alive for the
    // whole process even though `NSApplication.delegate` is a weak reference.
    let delegate = AppDelegate()
    application.delegate = delegate
    application.mainMenu = MainMenuBuilder.makeMainMenu(settingsTarget: delegate)
    application.run()
}
