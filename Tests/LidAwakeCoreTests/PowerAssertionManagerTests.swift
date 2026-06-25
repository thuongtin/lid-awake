import LidAwakeCore
import XCTest

final class PowerAssertionManagerTests: XCTestCase {
    func testAcquireIsIdempotent() throws {
        let creator = FakeAssertionCreator()
        let manager = PowerAssertionManager(creator: creator)
        let reason = WakeHoldReason(
            activeSessionIDs: ["1"],
            activeAgentNames: ["Codex CLI"],
            startedAt: Date(),
            note: "test"
        )

        try manager.acquire(reason: reason, preventDisplaySleep: true)
        try manager.acquire(reason: reason, preventDisplaySleep: true)

        XCTAssertTrue(manager.isHolding)
        XCTAssertEqual(creator.createdTypes, [.preventUserIdleSystemSleep, .preventUserIdleDisplaySleep])
    }

    func testAcquireAddsDisplayAssertionWhenModeChanges() throws {
        let creator = FakeAssertionCreator()
        let manager = PowerAssertionManager(creator: creator)
        let reason = WakeHoldReason(
            activeSessionIDs: ["1"],
            activeAgentNames: ["Codex CLI"],
            startedAt: Date(),
            note: "test"
        )

        try manager.acquire(reason: reason, preventDisplaySleep: false)
        try manager.acquire(reason: reason, preventDisplaySleep: true)

        XCTAssertTrue(manager.isHolding)
        XCTAssertEqual(creator.createdTypes, [.preventUserIdleSystemSleep, .preventUserIdleDisplaySleep])
    }

    func testAcquireReleasesDisplayAssertionWhenModeChanges() throws {
        let creator = FakeAssertionCreator()
        let manager = PowerAssertionManager(creator: creator)
        let reason = WakeHoldReason(
            activeSessionIDs: ["1"],
            activeAgentNames: ["Codex CLI"],
            startedAt: Date(),
            note: "test"
        )

        try manager.acquire(reason: reason, preventDisplaySleep: true)
        try manager.acquire(reason: reason, preventDisplaySleep: false)

        XCTAssertTrue(manager.isHolding)
        XCTAssertEqual(creator.createdTypes, [.preventUserIdleSystemSleep, .preventUserIdleDisplaySleep])
        XCTAssertEqual(creator.releasedIDs, [2])
    }

    func testReleaseReleasesAllAssertionsOnce() throws {
        let creator = FakeAssertionCreator()
        let manager = PowerAssertionManager(creator: creator)
        let reason = WakeHoldReason(
            activeSessionIDs: ["1"],
            activeAgentNames: ["Codex CLI"],
            startedAt: Date(),
            note: "test"
        )

        try manager.acquire(reason: reason, preventDisplaySleep: true)
        manager.release()
        manager.release()

        XCTAssertFalse(manager.isHolding)
        XCTAssertEqual(creator.releasedIDs, [2, 1])
    }

    func testDisplayFailureReleasesSystemAssertion() throws {
        let creator = FakeAssertionCreator()
        creator.failTypes = [.preventUserIdleDisplaySleep]
        let manager = PowerAssertionManager(creator: creator)
        let reason = WakeHoldReason(
            activeSessionIDs: ["1"],
            activeAgentNames: ["Codex CLI"],
            startedAt: Date(),
            note: "test"
        )

        XCTAssertThrowsError(try manager.acquire(reason: reason, preventDisplaySleep: true))
        XCTAssertFalse(manager.isHolding)
        XCTAssertEqual(creator.releasedIDs, [1])
    }

    func testDisplayAssertionCanBeDisabled() throws {
        let creator = FakeAssertionCreator()
        let manager = PowerAssertionManager(creator: creator)
        let reason = WakeHoldReason(
            activeSessionIDs: ["1"],
            activeAgentNames: ["Codex CLI"],
            startedAt: Date(),
            note: "test"
        )

        try manager.acquire(reason: reason, preventDisplaySleep: false)

        XCTAssertEqual(creator.createdTypes, [.preventUserIdleSystemSleep])
    }
}

private final class FakeAssertionCreator: PowerAssertionCreating {
    var nextID: UInt32 = 1
    var createdTypes: [PowerAssertionType] = []
    var releasedIDs: [UInt32] = []
    var failTypes: Set<PowerAssertionType> = []

    func createAssertion(type: PowerAssertionType, reason: String) throws -> UInt32 {
        if failTypes.contains(type) {
            throw PowerAssertionError.createFailed(type: type, code: -1)
        }

        let id = nextID
        nextID += 1
        createdTypes.append(type)
        return id
    }

    func releaseAssertion(id: UInt32) {
        releasedIDs.append(id)
    }
}
