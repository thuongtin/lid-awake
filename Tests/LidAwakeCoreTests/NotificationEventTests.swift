import LidAwakeCore
import XCTest

final class NotificationEventTests: XCTestCase {
    private let hold = WakeStatus.holding(
        WakeHoldReason(activeSessionIDs: ["a"], activeAgentNames: ["Agent"], startedAt: Date(), note: "")
    )

    func testBatteryCutoffNotifiesOnceAsTheBatteryKeepsDropping() {
        XCTAssertEqual(
            NotificationEvent.forTransition(from: .watching, to: .blocked(.batteryCutoff(percent: 19, cutoff: 20))),
            .batteryCutoff
        )
        XCTAssertNil(
            NotificationEvent.forTransition(
                from: .blocked(.batteryCutoff(percent: 19, cutoff: 20)),
                to: .blocked(.batteryCutoff(percent: 18, cutoff: 20))
            )
        )
    }

    func testLowPowerNotifiesOnlyWhenItIsEntered() {
        XCTAssertEqual(NotificationEvent.forTransition(from: .watching, to: .blocked(.lowPowerMode)), .lowPowerBlocked)
        XCTAssertNil(NotificationEvent.forTransition(from: .blocked(.lowPowerMode), to: .blocked(.lowPowerMode)))
    }

    func testMovingBetweenBlockReasonsNotifiesForTheNewReason() {
        XCTAssertEqual(
            NotificationEvent.forTransition(
                from: .blocked(.lowPowerMode),
                to: .blocked(.batteryCutoff(percent: 10, cutoff: 20))
            ),
            .batteryCutoff
        )
    }

    func testHoldTransitions() {
        XCTAssertEqual(NotificationEvent.forTransition(from: .watching, to: hold), .holdEngaged)
        XCTAssertNil(NotificationEvent.forTransition(from: hold, to: hold))
        XCTAssertEqual(NotificationEvent.forTransition(from: hold, to: .watching), .holdReleased)
        XCTAssertEqual(NotificationEvent.forTransition(from: hold, to: .inactive), .holdReleased)
        XCTAssertNil(NotificationEvent.forTransition(from: .watching, to: .watching))
    }
}
