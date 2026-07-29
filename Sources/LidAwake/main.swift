import AppKit

// Helper and diagnostic subcommands print to stdout and exit, so they must run
// before any AppKit state is created.
AppCommandRunner.runIfNeeded()

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
