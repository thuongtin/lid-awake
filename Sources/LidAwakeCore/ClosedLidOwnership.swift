import Foundation

public struct ClosedLidOwnershipRecord: Codable, Equatable, Sendable {
    public let ownedByThisApp: Bool
    public let enabledAt: Date?
    public let previousStatus: ClosedLidStatus
    public let lastAttemptedRestoreAt: Date?

    public init(
        ownedByThisApp: Bool,
        enabledAt: Date?,
        previousStatus: ClosedLidStatus,
        lastAttemptedRestoreAt: Date?
    ) {
        self.ownedByThisApp = ownedByThisApp
        self.enabledAt = enabledAt
        self.previousStatus = previousStatus
        self.lastAttemptedRestoreAt = lastAttemptedRestoreAt
    }
}

public protocol ClosedLidOwnershipStoring {
    func load() -> ClosedLidOwnershipRecord?
    func save(_ record: ClosedLidOwnershipRecord)
    func clear()
}

public final class UserDefaultsClosedLidOwnershipStore: ClosedLidOwnershipStoring {
    private let key: String
    private let defaults: UserDefaults

    public init(
        key: String = "LidAwake.closedLidOwnership",
        defaults: UserDefaults = .standard
    ) {
        self.key = key
        self.defaults = defaults
    }

    public func load() -> ClosedLidOwnershipRecord? {
        guard
            let data = defaults.data(forKey: key),
            let record = try? JSONDecoder().decode(ClosedLidOwnershipRecord.self, from: data)
        else {
            return nil
        }

        return record
    }

    public func save(_ record: ClosedLidOwnershipRecord) {
        guard let data = try? JSONEncoder().encode(record) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}

public enum ClosedLidOwnershipRestoreAction: Equatable, Sendable {
    case none
    case clearRecord
    case restore(ClosedLidOwnershipRecord)
    case blockedByHelper(ClosedLidOwnershipRecord)
}

public enum ClosedLidOwnershipRestoreCompletion: Equatable, Sendable {
    case clearRecord
    case keepRecord(errorMessage: String)
}

public enum ClosedLidOwnershipReducer {
    public static let restoreTimedOutMessage = "Timed out while restoring closed-lid mode. Lid Awake will retry on next launch."

    public static func recordAfterSuccessfulChange(
        enabled: Bool,
        previousStatus: ClosedLidStatus,
        finalStatus: ClosedLidStatus,
        existingRecord: ClosedLidOwnershipRecord?,
        at date: Date
    ) -> ClosedLidOwnershipRecord? {
        guard enabled else {
            return nil
        }

        guard previousStatus != .enabled, finalStatus == .enabled else {
            return existingRecord
        }

        return ClosedLidOwnershipRecord(
            ownedByThisApp: true,
            enabledAt: date,
            previousStatus: previousStatus,
            lastAttemptedRestoreAt: nil
        )
    }

    /// Claims ownership before the enable request is sent.
    ///
    /// The helper can apply `disablesleep 1` and still miss its reply deadline,
    /// and the app can quit or crash while the request is in flight. Recording
    /// only after a successful reply would leave the global setting on with
    /// nothing that knows to restore it. A claim made here is harmless when the
    /// enable never lands: restore clears it once the system reports disabled.
    public static func recordBeforeEnabling(
        previousStatus: ClosedLidStatus,
        existingRecord: ClosedLidOwnershipRecord?,
        at date: Date
    ) -> ClosedLidOwnershipRecord? {
        if let existingRecord, existingRecord.ownedByThisApp {
            return existingRecord
        }

        guard previousStatus != .enabled else {
            return existingRecord
        }

        return ClosedLidOwnershipRecord(
            ownedByThisApp: true,
            enabledAt: date,
            previousStatus: previousStatus,
            lastAttemptedRestoreAt: nil
        )
    }

    public static func restoreAction(
        record: ClosedLidOwnershipRecord?,
        desiredClosedLidMode: Bool,
        currentStatus: ClosedLidStatus,
        helperCanControlClosedLidMode: Bool,
        attemptedAt: Date
    ) -> ClosedLidOwnershipRestoreAction {
        guard let record, record.ownedByThisApp else {
            return .none
        }

        guard !desiredClosedLidMode else {
            return .none
        }

        // An unreadable status is not evidence that closed-lid mode is off, so
        // only a reported `.disabled` retires the record without a restore.
        guard currentStatus != .disabled else {
            return .clearRecord
        }

        let attemptedRecord = ClosedLidOwnershipRecord(
            ownedByThisApp: record.ownedByThisApp,
            enabledAt: record.enabledAt,
            previousStatus: record.previousStatus,
            lastAttemptedRestoreAt: attemptedAt
        )

        guard helperCanControlClosedLidMode else {
            return .blockedByHelper(attemptedRecord)
        }

        return .restore(attemptedRecord)
    }

    public static func restoreCompletion(
        didComplete: Bool,
        errorMessage: String?
    ) -> ClosedLidOwnershipRestoreCompletion {
        guard didComplete else {
            return .keepRecord(errorMessage: restoreTimedOutMessage)
        }

        if let errorMessage, !errorMessage.isEmpty {
            return .keepRecord(errorMessage: errorMessage)
        }

        return .clearRecord
    }
}
