import LidAwakeCore
import Foundation

enum ClosedLidHelperRemovalError: LocalizedError, Equatable {
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case let .restoreFailed(message):
            "Closed-lid mode must be restored before removing Lid Awake Helper: \(message)"
        }
    }
}

/// Removes the helper outside the running app, for `--helper-remove`.
///
/// Unregistering the helper while this app still owns closed-lid mode would
/// leave `pmset disablesleep 1` set with nothing able to turn it back off, so
/// this restores first and keeps the helper whenever restore does not finish.
enum ClosedLidHelperRemoval {
    static let restoreTimeout: TimeInterval = 5

    static func removeHelper(
        helperService: ClosedLidHelperServicing,
        statusReader: ClosedLidStatusReading,
        ownershipStore: ClosedLidOwnershipStoring,
        restoreTimeout: TimeInterval = restoreTimeout
    ) throws {
        try restoreOwnedClosedLidMode(
            helperService: helperService,
            statusReader: statusReader,
            ownershipStore: ownershipStore,
            restoreTimeout: restoreTimeout
        )
        try helperService.unregister()
    }

    private static func restoreOwnedClosedLidMode(
        helperService: ClosedLidHelperServicing,
        statusReader: ClosedLidStatusReading,
        ownershipStore: ClosedLidOwnershipStoring,
        restoreTimeout: TimeInterval
    ) throws {
        switch ClosedLidOwnershipReducer.restoreAction(
            record: ownershipStore.load(),
            desiredClosedLidMode: false,
            currentStatus: statusReader.readClosedLidStatus(),
            helperCanControlClosedLidMode: helperService.status.canControlClosedLidMode,
            attemptedAt: Date()
        ) {
        case .none:
            return
        case .clearRecord:
            ownershipStore.clear()
            return
        case let .blockedByHelper(record):
            ownershipStore.save(record)
            throw ClosedLidHelperRemovalError.restoreFailed("Advanced Helper is not ready.")
        case let .restore(record):
            ownershipStore.save(record)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var restoreError: Error?
        helperService.setClosedLidMode(enabled: false) { result in
            if case let .failure(error) = result {
                restoreError = error
            }
            semaphore.signal()
        }
        let didComplete = semaphore.wait(timeout: .now() + restoreTimeout) == .success

        switch ClosedLidOwnershipReducer.restoreCompletion(
            didComplete: didComplete,
            errorMessage: restoreError?.localizedDescription
        ) {
        case .clearRecord:
            ownershipStore.clear()
        case let .keepRecord(errorMessage):
            throw ClosedLidHelperRemovalError.restoreFailed(errorMessage)
        }
    }
}
