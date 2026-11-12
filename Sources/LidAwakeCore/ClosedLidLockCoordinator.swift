import Foundation

public protocol DeviceLocking: AnyObject {
    func lockScreenNow() throws
}

public enum ClosedLidLockAction: Equatable, Sendable {
    case none
    case requestedLock
    case failed(String)
}

public final class ClosedLidLockCoordinator {
    public static let lockNotObservedMessage =
        "macOS did not lock the screen when the lid closed. Lock it from the Apple menu, then check System Settings > Lock Screen."

    private let clamshellStateReader: ClamshellStateReading
    private let deviceLocker: DeviceLocking
    private let screenLockStateReader: ScreenLockStateReading?
    private let maximumLockRequests: Int
    private let lockVerificationUpdates: Int
    private var lockRequestCount = 0
    private var lastClamshellState: ClamshellState?
    /// Updates seen since a lock request, while it is still unconfirmed.
    private var updatesSinceLockRequest: Int?
    private var isActingOnClosure = false

    /// Changes whenever a lid closure the coordinator acts on starts or ends,
    /// so a lock command that fails after its closure ended can be told apart
    /// from one that failed for the current closure.
    public private(set) var lidClosureID = 0

    /// - Parameter screenLockStateReader: When set, a lock request that has not
    ///   locked the screen after `lockVerificationUpdates` more updates is
    ///   reported as failed. A request can be swallowed, for example a lock
    ///   shortcut the user turned off, without ever returning an error.
    public init(
        clamshellStateReader: ClamshellStateReading,
        deviceLocker: DeviceLocking,
        screenLockStateReader: ScreenLockStateReading? = nil,
        maximumLockRequests: Int = 1,
        lockVerificationUpdates: Int = 3
    ) {
        self.clamshellStateReader = clamshellStateReader
        self.deviceLocker = deviceLocker
        self.screenLockStateReader = screenLockStateReader
        self.maximumLockRequests = max(1, maximumLockRequests)
        self.lockVerificationUpdates = max(1, lockVerificationUpdates)
    }

    @discardableResult
    public func update(settings: UserSettings) -> ClosedLidLockAction {
        let clamshellState = clamshellStateReader.clamshellState()
        let previousClamshellState = lastClamshellState
        lastClamshellState = clamshellState

        guard clamshellState == .closed else {
            endClosure()
            lockRequestCount = 0
            updatesSinceLockRequest = nil
            return .none
        }

        guard settings.enabled, settings.lockScreenWhenLidCloses else {
            endClosure()
            lockRequestCount = maximumLockRequests
            updatesSinceLockRequest = nil
            return .none
        }

        guard let previousClamshellState else {
            lockRequestCount = maximumLockRequests
            return .none
        }

        if previousClamshellState == .open {
            endClosure()
            isActingOnClosure = true
            lidClosureID &+= 1
            lockRequestCount = 0
            updatesSinceLockRequest = nil
        } else if previousClamshellState != .closed {
            endClosure()
            lockRequestCount = maximumLockRequests
            return .none
        }

        if let updates = updatesSinceLockRequest {
            return verifyLock(updatesSoFar: updates)
        }

        guard lockRequestCount < maximumLockRequests else {
            return .none
        }

        do {
            try deviceLocker.lockScreenNow()
            lockRequestCount += 1
            updatesSinceLockRequest = screenLockStateReader == nil ? nil : 0
            return .requestedLock
        } catch {
            lockRequestCount += 1
            return .failed(error.localizedDescription)
        }
    }

    public func reset() {
        lockRequestCount = maximumLockRequests
        updatesSinceLockRequest = nil
    }

    /// Drops the last clamshell state seen, for a stretch where the caller
    /// stops calling `update`. A lid that closed in that stretch is then not
    /// taken for a close the user just made.
    public func forgetLidState() {
        endClosure()
        lastClamshellState = nil
        updatesSinceLockRequest = nil
    }

    private func endClosure() {
        guard isActingOnClosure else {
            return
        }

        isActingOnClosure = false
        lidClosureID &+= 1
    }

    private func verifyLock(updatesSoFar: Int) -> ClosedLidLockAction {
        // Only a reader that reports the screen unlocked counts against the
        // request; one that cannot tell gets the benefit of the doubt.
        guard screenLockStateReader?.screenLockState() == .unlocked else {
            updatesSinceLockRequest = nil
            return .none
        }

        let updates = updatesSoFar + 1
        guard updates >= lockVerificationUpdates else {
            updatesSinceLockRequest = updates
            return .none
        }

        updatesSinceLockRequest = nil
        return .failed(Self.lockNotObservedMessage)
    }
}
