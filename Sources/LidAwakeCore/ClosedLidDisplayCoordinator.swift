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
    /// Returns false when an earlier request is still running and this one
    /// was folded into it, so no new command started.
    @discardableResult
    func sleepDisplaysNow() throws -> Bool
}

public enum ScreenLockState: Equatable, Sendable {
    case locked
    case unlocked
    case unavailable
}

public protocol ScreenLockStateReading: AnyObject {
    func screenLockState() -> ScreenLockState
}

public enum ClosedLidDisplayAction: Equatable, Sendable {
    case none
    case requestedDisplaySleep
    case failed(String)
}

public final class ClosedLidDisplayCoordinator {
    private let clamshellStateReader: ClamshellStateReading
    private let displaySleeper: DisplaySleeping
    private let screenLockStateReader: ScreenLockStateReading?
    private let maximumDisplaySleepRequests: Int
    private var displaySleepRequestCount = 0
    private var lastClamshellState: ClamshellState?
    private var observedClosedTransition = false

    /// Changes whenever a lid closure the coordinator acts on starts or ends,
    /// so a display sleep command that fails after its closure ended can be
    /// told apart from one that failed for the current closure.
    public private(set) var lidClosureID = 0

    public init(
        clamshellStateReader: ClamshellStateReading,
        displaySleeper: DisplaySleeping,
        screenLockStateReader: ScreenLockStateReading? = nil,
        maximumDisplaySleepRequests: Int = 3
    ) {
        self.clamshellStateReader = clamshellStateReader
        self.displaySleeper = displaySleeper
        self.screenLockStateReader = screenLockStateReader
        self.maximumDisplaySleepRequests = max(1, maximumDisplaySleepRequests)
    }

    @discardableResult
    public func update(
        settings: UserSettings,
        wakeStatus: WakeStatus,
        closedLidStatus: ClosedLidStatus,
        waitForScreenLockBeforeDisplaySleep: Bool = true
    ) -> ClosedLidDisplayAction {
        let clamshellState = clamshellStateReader.clamshellState()
        let previousClamshellState = lastClamshellState
        lastClamshellState = clamshellState

        guard clamshellState == .closed else {
            resetClosedLidTransition()
            return .none
        }

        guard let previousClamshellState else {
            observedClosedTransition = false
            displaySleepRequestCount = maximumDisplaySleepRequests
            return .none
        }

        if previousClamshellState == .open {
            observedClosedTransition = settings.lidClosedDisplayMode == .turnDisplayOff
            if observedClosedTransition {
                lidClosureID &+= 1
            }
            displaySleepRequestCount = 0
        } else if previousClamshellState != .closed {
            observedClosedTransition = false
            displaySleepRequestCount = maximumDisplaySleepRequests
            return .none
        }

        guard observedClosedTransition else {
            return .none
        }

        guard settings.lidClosedDisplayMode == .turnDisplayOff else {
            resetClosedLidTransition()
            return .none
        }

        guard closedLidStatus == .enabled else {
            return .none
        }

        guard case .holding = wakeStatus else {
            resetClosedLidTransition()
            return .none
        }

        if settings.lockScreenWhenLidCloses, waitForScreenLockBeforeDisplaySleep {
            switch screenLockStateReader?.screenLockState() {
            case .locked, .unavailable, nil:
                break
            case .unlocked:
                return .none
            }
        }

        guard displaySleepRequestCount < maximumDisplaySleepRequests else {
            return .none
        }

        do {
            // A request folded into one still running is not an attempt, or
            // one slow command could use up every retry for this closure.
            guard try displaySleeper.sleepDisplaysNow() else {
                return .none
            }

            displaySleepRequestCount += 1
            return .requestedDisplaySleep
        } catch {
            displaySleepRequestCount += 1
            return .failed(error.localizedDescription)
        }
    }

    /// Drops the last clamshell state seen, for a stretch where the caller
    /// stops calling `update`. A lid that closed in that stretch is then not
    /// taken for a close the user just made.
    public func forgetLidState() {
        lastClamshellState = nil
        resetClosedLidTransition()
    }

    private func resetClosedLidTransition() {
        if observedClosedTransition {
            lidClosureID &+= 1
        }
        displaySleepRequestCount = 0
        observedClosedTransition = false
    }
}
