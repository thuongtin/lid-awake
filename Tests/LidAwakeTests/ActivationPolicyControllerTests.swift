@testable import LidAwake
import XCTest

@MainActor
final class ActivationPolicyControllerTests: XCTestCase {
    func testFirstReasonBringsTheAppToTheForeground() {
        let applier = RecordingActivationPolicyApplier()
        let controller = ActivationPolicyController(applier: applier)

        controller.beginForeground(.settingsWindow)

        XCTAssertEqual(applier.events, [.foreground])
    }

    func testEveryReasonReactivatesSoALaterWindowStillTakesFocus() {
        let applier = RecordingActivationPolicyApplier()
        let controller = ActivationPolicyController(applier: applier)

        controller.beginForeground(.settingsWindow)
        controller.beginForeground(.updateSession)

        XCTAssertEqual(applier.events, [.foreground, .foreground])
    }

    func testReleasingTheLastReasonReturnsToAccessory() {
        let applier = RecordingActivationPolicyApplier()
        let controller = ActivationPolicyController(applier: applier)

        controller.beginForeground(.updateSession)
        controller.endForeground(.updateSession)

        XCTAssertEqual(applier.events, [.foreground, .background])
        XCTAssertTrue(controller.foregroundReasons.isEmpty)
    }

    func testUpdateSessionEndingKeepsTheAppForegroundWhileSettingsIsOpen() {
        let applier = RecordingActivationPolicyApplier()
        let controller = ActivationPolicyController(applier: applier)

        controller.beginForeground(.settingsWindow)
        controller.beginForeground(.updateSession)
        controller.endForeground(.updateSession)

        XCTAssertEqual(applier.events, [.foreground, .foreground])
        XCTAssertEqual(controller.foregroundReasons, [.settingsWindow])

        controller.endForeground(.settingsWindow)

        XCTAssertEqual(applier.events, [.foreground, .foreground, .background])
    }

    func testReleasingAReasonTwiceDoesNotResignAgain() {
        let applier = RecordingActivationPolicyApplier()
        let controller = ActivationPolicyController(applier: applier)

        controller.beginForeground(.permissionPrompt)
        controller.endForeground(.permissionPrompt)
        controller.beginForeground(.settingsWindow)
        controller.endForeground(.permissionPrompt)

        XCTAssertEqual(applier.events, [.foreground, .background, .foreground])
        XCTAssertEqual(controller.foregroundReasons, [.settingsWindow])
    }
}

@MainActor
private final class RecordingActivationPolicyApplier: ActivationPolicyApplying {
    enum Event: Equatable {
        case foreground
        case background
    }

    private(set) var events: [Event] = []

    func activateAsForegroundApp() {
        events.append(.foreground)
    }

    func resignForegroundApp() {
        events.append(.background)
    }
}
