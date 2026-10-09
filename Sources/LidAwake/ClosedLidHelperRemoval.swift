import LidAwakeCore
import Foundation

enum ClosedLidHelperRemovalError: LocalizedError, Equatable {
    case restoreFailed(String)
    case appIsRunning

    var errorDescription: String? {
        switch self {
        case let .restoreFailed(message):
            "Closed-lid mode must be restored before removing Lid Awake Helper: \(message)"
        case .appIsRunning:
            "Lid Awake is running. Quit it first, or remove the helper from Lid Awake Settings."
        }
    }
}

/// Removes the helper outside the running app, for `--helper-remove`.
///
/// Unregistering the helper while this app still owns closed-lid mode would
/// leave `pmset disablesleep 1` set with nothing able to turn it back off, so
/// this restores first and keeps the helper whenever restore does not finish.
///
/// A running copy of the app can have an enable on its way to the helper that
/// this process cannot see, and it can land between the restore and the
/// unregister, so removal is refused while the app is running. The app's own
/// Remove holds back its changes while it removes the helper.
enum ClosedLidHelperRemoval {
    static let restoreTimeout: TimeInterval = 5

    static func removeHelper(
        helperService: ClosedLidHelperServicing,
        statusReader: ClosedLidStatusReading,
        ownershipStore: ClosedLidOwnershipStoring,
        appIsRunning: Bool,
        restoreTimeout: TimeInterval = restoreTimeout
    ) throws {
        guard !appIsRunning else {
            throw ClosedLidHelperRemovalError.appIsRunning
        }

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
        // An enable already queued in the helper can land after any read, so
        // a helper that can change the mode is asked to turn it off whatever
        // `pmset` reports, which is harmless when it is already off. One that
        // cannot change it has nothing queued, and a read is all there is.
        let helperCanControlClosedLidMode = helperService.status.canControlClosedLidMode
        switch ClosedLidOwnershipReducer.restoreAction(
            record: ownershipStore.load(),
            desiredClosedLidMode: false,
            currentStatus: helperCanControlClosedLidMode ? .enabled : statusReader.readClosedLidStatus(),
            helperCanControlClosedLidMode: helperCanControlClosedLidMode,
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
