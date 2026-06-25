import LidAwakeCore
import XCTest

final class NotificationDeduplicatorTests: XCTestCase {
    func testSuppressesDuplicateInsideWindow() {
        let clock = FakeClock()
        let deduplicator = NotificationDeduplicator(clock: clock, window: 60)

        XCTAssertTrue(deduplicator.shouldSend(.holdEngaged))
        XCTAssertFalse(deduplicator.shouldSend(.holdEngaged))
    }

    func testAllowsDuplicateAfterWindow() {
        let clock = FakeClock()
        let deduplicator = NotificationDeduplicator(clock: clock, window: 60)

        XCTAssertTrue(deduplicator.shouldSend(.holdEngaged))
        clock.advance(seconds: 61)
        XCTAssertTrue(deduplicator.shouldSend(.holdEngaged))
    }

    func testDifferentEventsDoNotDeduplicateEachOther() {
        let clock = FakeClock()
        let deduplicator = NotificationDeduplicator(clock: clock, window: 60)

        XCTAssertTrue(deduplicator.shouldSend(.holdEngaged))
        XCTAssertTrue(deduplicator.shouldSend(.batteryCutoff))
    }
}
