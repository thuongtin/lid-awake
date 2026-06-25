import LidAwakeCore
import XCTest

final class ClosedLidOwnershipTests: XCTestCase {
    func testOwnershipRecordEncodesAndDecodes() throws {
        let enabledAt = Date(timeIntervalSince1970: 1_800_000_000)
        let attemptedAt = Date(timeIntervalSince1970: 1_800_000_300)
        let record = ClosedLidOwnershipRecord(
            ownedByThisApp: true,
            enabledAt: enabledAt,
            previousStatus: .disabled,
            lastAttemptedRestoreAt: attemptedAt
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ClosedLidOwnershipRecord.self, from: data)

        XCTAssertEqual(decoded, record)
    }

    func testOwnershipStoreRoundTripsRecord() {
        let store = InMemoryClosedLidOwnershipStore()
        let record = ClosedLidOwnershipRecord(
            ownedByThisApp: true,
            enabledAt: Date(timeIntervalSince1970: 1_800_000_000),
            previousStatus: .notReported,
            lastAttemptedRestoreAt: nil
        )

        store.save(record)

        XCTAssertEqual(store.load(), record)
    }

    func testOwnershipStoreClearsRecord() {
        let store = InMemoryClosedLidOwnershipStore()
        store.save(ClosedLidOwnershipRecord(
            ownedByThisApp: true,
            enabledAt: Date(timeIntervalSince1970: 1_800_000_000),
            previousStatus: .disabled,
            lastAttemptedRestoreAt: nil
        ))

        store.clear()

        XCTAssertNil(store.load())
    }

    func testPreExistingEnabledStatusDoesNotCreateOwnership() {
        let record = ClosedLidOwnershipReducer.recordAfterSuccessfulChange(
            enabled: true,
            previousStatus: .enabled,
            finalStatus: .enabled,
            existingRecord: nil,
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertNil(record)
    }

    func testSuccessfulEnableFromDisabledCreatesOwnership() {
        let enabledAt = Date(timeIntervalSince1970: 1_800_000_000)

        let record = ClosedLidOwnershipReducer.recordAfterSuccessfulChange(
            enabled: true,
            previousStatus: .disabled,
            finalStatus: .enabled,
            existingRecord: nil,
            at: enabledAt
        )

        XCTAssertEqual(record, ClosedLidOwnershipRecord(
            ownedByThisApp: true,
            enabledAt: enabledAt,
            previousStatus: .disabled,
            lastAttemptedRestoreAt: nil
        ))
    }

    func testSuccessfulDisableClearsOwnership() {
        let existingRecord = ClosedLidOwnershipRecord(
            ownedByThisApp: true,
            enabledAt: Date(timeIntervalSince1970: 1_800_000_000),
            previousStatus: .disabled,
            lastAttemptedRestoreAt: nil
        )

        let record = ClosedLidOwnershipReducer.recordAfterSuccessfulChange(
            enabled: false,
            previousStatus: .enabled,
            finalStatus: .disabled,
            existingRecord: existingRecord,
            at: Date(timeIntervalSince1970: 1_800_000_500)
        )

        XCTAssertNil(record)
    }

    func testStartupCleanupTriesRestoreWhenPersistedOwnershipExists() {
        let attemptedAt = Date(timeIntervalSince1970: 1_800_000_600)
        let record = ownedRecord()

        let action = ClosedLidOwnershipReducer.restoreAction(
            record: record,
            desiredClosedLidMode: false,
            currentStatus: .enabled,
            helperCanControlClosedLidMode: true,
            attemptedAt: attemptedAt
        )

        XCTAssertEqual(action, .restore(ClosedLidOwnershipRecord(
            ownedByThisApp: true,
            enabledAt: record.enabledAt,
            previousStatus: .disabled,
            lastAttemptedRestoreAt: attemptedAt
        )))
    }

    func testStartupCleanupLeavesWarningStateWhenHelperIsNotReady() {
        let attemptedAt = Date(timeIntervalSince1970: 1_800_000_600)
        let record = ownedRecord()

        let action = ClosedLidOwnershipReducer.restoreAction(
            record: record,
            desiredClosedLidMode: false,
            currentStatus: .enabled,
            helperCanControlClosedLidMode: false,
            attemptedAt: attemptedAt
        )

        XCTAssertEqual(action, .blockedByHelper(ClosedLidOwnershipRecord(
            ownedByThisApp: true,
            enabledAt: record.enabledAt,
            previousStatus: .disabled,
            lastAttemptedRestoreAt: attemptedAt
        )))
    }

    func testStartupCleanupDoesNotRestoreWhenClosedLidModeIsStillDesired() {
        let action = ClosedLidOwnershipReducer.restoreAction(
            record: ownedRecord(),
            desiredClosedLidMode: true,
            currentStatus: .enabled,
            helperCanControlClosedLidMode: true,
            attemptedAt: Date(timeIntervalSince1970: 1_800_000_600)
        )

        XCTAssertEqual(action, .none)
    }

    func testStartupCleanupClearsOwnershipWhenSystemIsAlreadyDisabled() {
        let action = ClosedLidOwnershipReducer.restoreAction(
            record: ownedRecord(),
            desiredClosedLidMode: false,
            currentStatus: .disabled,
            helperCanControlClosedLidMode: false,
            attemptedAt: Date(timeIntervalSince1970: 1_800_000_600)
        )

        XCTAssertEqual(action, .clearRecord)
    }

    func testRestoreCompletionTimeoutKeepsOwnershipRecord() {
        let completion = ClosedLidOwnershipReducer.restoreCompletion(
            didComplete: false,
            errorMessage: nil
        )

        XCTAssertEqual(completion, .keepRecord(errorMessage: ClosedLidOwnershipReducer.restoreTimedOutMessage))
    }

    func testRestoreCompletionFailureKeepsOwnershipRecord() {
        let completion = ClosedLidOwnershipReducer.restoreCompletion(
            didComplete: true,
            errorMessage: "Helper failed"
        )

        XCTAssertEqual(completion, .keepRecord(errorMessage: "Helper failed"))
    }

    func testRestoreCompletionSuccessClearsOwnershipRecord() {
        let completion = ClosedLidOwnershipReducer.restoreCompletion(
            didComplete: true,
            errorMessage: nil
        )

        XCTAssertEqual(completion, .clearRecord)
    }
}

private func ownedRecord() -> ClosedLidOwnershipRecord {
    ClosedLidOwnershipRecord(
        ownedByThisApp: true,
        enabledAt: Date(timeIntervalSince1970: 1_800_000_000),
        previousStatus: .disabled,
        lastAttemptedRestoreAt: nil
    )
}

private final class InMemoryClosedLidOwnershipStore: ClosedLidOwnershipStoring {
    private var record: ClosedLidOwnershipRecord?

    func load() -> ClosedLidOwnershipRecord? {
        record
    }

    func save(_ record: ClosedLidOwnershipRecord) {
        self.record = record
    }

    func clear() {
        record = nil
    }
}
