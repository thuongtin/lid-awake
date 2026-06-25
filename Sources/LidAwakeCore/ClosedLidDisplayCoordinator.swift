import Foundation

public enum ClamshellState: Equatable, Sendable {
    case open
    case closed
    case unavailable
}

public protocol ClamshellStateReading: AnyObject {
    func clamshellState() -> ClamshellState
}

public protocol DisplaySleeping: AnyObject {
    func sleepDisplaysNow() throws
}

public enum ClosedLidDisplayAction: Equatable, Sendable {
    case none
    case requestedDisplaySleep
    case failed(String)
}

public final class ClosedLidDisplayCoordinator {
    private let clamshellStateReader: ClamshellStateReading
    private let displaySleeper: DisplaySleeping
    private var didRequestDisplaySleepForCurrentClosure = false

    public init(
        clamshellStateReader: ClamshellStateReading,
        displaySleeper: DisplaySleeping
    ) {
        self.clamshellStateReader = clamshellStateReader
        self.displaySleeper = displaySleeper
    }

    @discardableResult
    public func update(
        settings: UserSettings,
        wakeStatus: WakeStatus,
        closedLidStatus: ClosedLidStatus
    ) -> ClosedLidDisplayAction {
        let clamshellState = clamshellStateReader.clamshellState()
        guard clamshellState == .closed else {
            didRequestDisplaySleepForCurrentClosure = false
            return .none
        }

        guard settings.lidClosedDisplayMode == .turnDisplayOff else {
            return .none
        }

        guard closedLidStatus == .enabled else {
            return .none
        }

        guard case .holding = wakeStatus else {
            return .none
        }

        guard !didRequestDisplaySleepForCurrentClosure else {
            return .none
        }

        do {
            try displaySleeper.sleepDisplaysNow()
            didRequestDisplaySleepForCurrentClosure = true
            return .requestedDisplaySleep
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
