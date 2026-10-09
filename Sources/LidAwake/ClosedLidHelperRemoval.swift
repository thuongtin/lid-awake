import LidAwakeCore
import Foundation

enum ClosedLidHelperRemovalError: LocalizedError, Equatable {
    case restoreFailed(String)
    case appIsRunning
    case appIsRunningForRepair

    var errorDescription: String? {
        switch self {
        case let .restoreFailed(message):
            "Closed-lid mode must be restored before removing Lid Awake Helper: \(message)"
        case .appIsRunning:
            "Lid Awake is running. Quit it first, or remove the helper from Lid Awake Settings."
        case .appIsRunningForRepair:
            "Lid Awake is running. Quit it first, or repair the helper from Lid Awake Settings."
        }
    }
}

/// Removes or repairs the helper outside the running app, for
/// `--helper-remove` and `--helper-repair`.
///
/// Unregistering the helper while this app still owns closed-lid mode would
/// leave `pmset disablesleep 1` set with nothing able to turn it back off, so
/// this restores first and keeps the helper whenever restore does not finish.
///
/// A running copy of the app can have an enable on its way to the helper that
/// this process cannot see, and it can land between the restore and the
/// unregister, so both are refused while the app is running. The app's own
/// Remove and Repair hold back its changes while they replace the helper.
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
        ).mapError { ClosedLidHelperRemovalError.restoreFailed($0.message) }.get()
        try helperService.unregister()
    }

    /// Re-registers the helper, restoring closed-lid mode the app left owned.
    ///
    /// No copy of the app is running, so a mode it still owns was left on by
    /// one that crashed, and nothing is left to want it on. The old helper may
    /// still be retrying that restore, and unregistering it drops the retries,
    /// so this restores through it first. A helper that does not answer is
    /// usually why a repair is run, so the repair then goes ahead and restores
    /// through the new helper instead. One that answers but cannot restore
    /// keeps its retries, so the repair stops there.
    static func repairHelper(
        helperService: ClosedLidHelperServicing,
        statusReader: ClosedLidStatusReading,
        ownershipStore: ClosedLidOwnershipStoring,
        appIsRunning: Bool,
        restoreTimeout: TimeInterval = restoreTimeout,
        repairRegistration: () throws -> Void
    ) throws {
        guard !appIsRunning else {
            throw ClosedLidHelperRemovalError.appIsRunningForRepair
        }

        let restoreBeforeRepair = restoreOwnedClosedLidMode(
            helperService: helperService,
            statusReader: statusReader,
            ownershipStore: ownershipStore,
            restoreTimeout: restoreTimeout
        )
        if case let .failure(failure) = restoreBeforeRepair, failure.helperAnswered {
            throw ClosedLidHelperRemovalError.restoreFailed(failure.message)
        }

        try repairRegistration()

        guard case .failure = restoreBeforeRepair else {
            return
        }

        try restoreOwnedClosedLidMode(
            helperService: helperService,
            statusReader: statusReader,
            ownershipStore: ownershipStore,
            restoreTimeout: restoreTimeout
        ).mapError { ClosedLidHelperRemovalError.restoreFailed($0.message) }.get()
    }

    private struct RestoreFailure: Error {
        let message: String
        /// The helper ran the restore and reported that it failed, so it is
        /// reachable and still watching for the app it last served.
        let helperAnswered: Bool
    }

    private static func restoreOwnedClosedLidMode(
        helperService: ClosedLidHelperServicing,
        statusReader: ClosedLidStatusReading,
        ownershipStore: ClosedLidOwnershipStoring,
        restoreTimeout: TimeInterval
    ) -> Result<Void, RestoreFailure> {
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
            return .success(())
        case .clearRecord:
            ownershipStore.clear()
            return .success(())
        case let .blockedByHelper(record):
            ownershipStore.save(record)
            return .failure(RestoreFailure(message: "Advanced Helper is not ready.", helperAnswered: false))
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
            return .success(())
        case let .keepRecord(errorMessage):
            let helperAnswered = didComplete
                && (restoreError as? ClosedLidHelperFailure)?.isRecoverableByRepair != true
            return .failure(RestoreFailure(message: errorMessage, helperAnswered: helperAnswered))
        }
    }
}
