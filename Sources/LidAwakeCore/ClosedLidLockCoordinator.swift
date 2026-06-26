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
    private var didLockForCurrentClosure = false

    public init(
        clamshellStateReader: ClamshellStateReading,
        deviceLocker: DeviceLocking
    ) {
        self.clamshellStateReader = clamshellStateReader
        self.deviceLocker = deviceLocker
    }

    @discardableResult
    public func update(settings: UserSettings) -> ClosedLidLockAction {
        let clamshellState = clamshellStateReader.clamshellState()
        guard clamshellState == .closed else {
            didLockForCurrentClosure = false
            return .none
        }

        guard settings.enabled, settings.lockScreenWhenLidCloses else {
            return .none
        }

        guard !didLockForCurrentClosure else {
            return .none
        }

        do {
            try deviceLocker.lockScreenNow()
            didLockForCurrentClosure = true
            return .requestedLock
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
