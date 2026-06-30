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
    private let clamshellStateReader: ClamshellStateReading
    private let deviceLocker: DeviceLocking
    private let maximumLockRequests: Int
    private var lockRequestCount = 0
    private var lastClamshellState: ClamshellState?

    public init(
        clamshellStateReader: ClamshellStateReading,
        deviceLocker: DeviceLocking,
        maximumLockRequests: Int = 1
    ) {
        self.clamshellStateReader = clamshellStateReader
        self.deviceLocker = deviceLocker
        self.maximumLockRequests = max(1, maximumLockRequests)
    }

    @discardableResult
    public func update(settings: UserSettings) -> ClosedLidLockAction {
        let clamshellState = clamshellStateReader.clamshellState()
        let previousClamshellState = lastClamshellState
        lastClamshellState = clamshellState

        guard clamshellState == .closed else {
            lockRequestCount = 0
            return .none
        }

        guard settings.enabled, settings.lockScreenWhenLidCloses else {
            lockRequestCount = maximumLockRequests
            return .none
        }

        guard let previousClamshellState else {
            lockRequestCount = maximumLockRequests
            return .none
        }

        if previousClamshellState == .open {
            lockRequestCount = 0
        } else if previousClamshellState != .closed {
            lockRequestCount = maximumLockRequests
            return .none
        }

        guard lockRequestCount < maximumLockRequests else {
            return .none
        }

        do {
            try deviceLocker.lockScreenNow()
            lockRequestCount += 1
            return .requestedLock
        } catch {
            lockRequestCount += 1
            return .failed(error.localizedDescription)
        }
    }

    public func reset() {
        lockRequestCount = maximumLockRequests
    }
}
