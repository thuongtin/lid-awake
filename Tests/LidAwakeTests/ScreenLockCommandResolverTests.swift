@testable import LidAwake
import XCTest

final class ScreenLockCommandResolverTests: XCTestCase {
    func testPrefersCGSessionWhenAvailable() {
        let command = ScreenLockCommandResolver.resolve(
            isExecutable: { path in
                path == ScreenLockCommandResolver.cgSessionPath
                    || path == ScreenLockCommandResolver.openPath
            },
            fileExists: { path in
                path == ScreenLockCommandResolver.screenSaverAppPath
            }
        )

        XCTAssertEqual(
            command,
            ScreenLockCommand(
                executablePath: ScreenLockCommandResolver.cgSessionPath,
                arguments: ["-suspend"]
            )
        )
    }

    func testFallsBackToScreenSaverEngineWhenCGSessionIsMissing() {
        let command = ScreenLockCommandResolver.resolve(
            isExecutable: { path in
                path == ScreenLockCommandResolver.openPath
            },
            fileExists: { path in
                path == ScreenLockCommandResolver.screenSaverAppPath
            }
        )

        XCTAssertEqual(
            command,
            ScreenLockCommand(
                executablePath: ScreenLockCommandResolver.openPath,
                arguments: [ScreenLockCommandResolver.screenSaverAppPath]
            )
        )
    }

    func testReturnsNilWhenNoSupportedCommandIsAvailable() {
        let command = ScreenLockCommandResolver.resolve(
            isExecutable: { _ in false },
            fileExists: { _ in false }
        )

        XCTAssertNil(command)
    }
}
