@testable import LidAwake
import XCTest

final class ScreenLockCommandResolverTests: XCTestCase {
    func testPrefersCGSessionWhenAvailable() {
        let method = ScreenLockCommandResolver.resolve(
            isExecutable: { path in
                path == ScreenLockCommandResolver.cgSessionPath
            }
        )

        XCTAssertEqual(
            method,
            .command(
                ScreenLockCommand(
                    executablePath: ScreenLockCommandResolver.cgSessionPath,
                    arguments: ["-suspend"]
                )
            )
        )
    }

    func testFallsBackToKeyboardShortcutWhenCGSessionIsMissing() {
        let method = ScreenLockCommandResolver.resolve(isExecutable: { _ in false })

        XCTAssertEqual(method, .keyboardShortcut)
    }
}
