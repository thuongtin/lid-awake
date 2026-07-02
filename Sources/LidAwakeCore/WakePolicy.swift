import Foundation

public struct WakeHoldReason: Equatable, Sendable {
    public var activeSessionIDs: [String]
    public var activeAgentNames: [String]
    public var startedAt: Date
    public var note: String

    public init(
        activeSessionIDs: [String],
        activeAgentNames: [String],
        startedAt: Date,
        note: String
    ) {
        self.activeSessionIDs = activeSessionIDs
        self.activeAgentNames = activeAgentNames
        self.startedAt = startedAt
        self.note = note
    }

    public var assertionReason: String {
        "Lid Awake keeping Mac awake"
    }
}

public enum WakeBlockReason: Equatable, Sendable {
    case disabled
    case paused(until: Date)
    case noActiveAgent
    case batteryCutoff(percent: Int, cutoff: Int)
    case notPluggedIn
    case lowPowerMode
    case assertionFailed(String)

    public var displayText: String {
        switch self {
        case .disabled:
            "Disabled"
        case let .paused(until):
            "Paused until \(until.formatted(date: .omitted, time: .shortened))"
        case .noActiveAgent:
            "Ready"
        case let .batteryCutoff(percent, cutoff):
            "Battery \(percent)% is at or below cutoff \(cutoff)%"
        case .notPluggedIn:
            "Waiting for power adapter"
        case .lowPowerMode:
            "Blocked by Low Power Mode"
        case let .assertionFailed(message):
            "Power assertion failed: \(message)"
        }
    }
}

public enum WakeStatus: Equatable, Sendable {
    case inactive
    case watching
    case holding(WakeHoldReason)
    case paused(until: Date)
    case blocked(WakeBlockReason)

    public var displayText: String {
        switch self {
        case .inactive:
            return "Inactive"
        case .watching:
            return "Ready"
        case let .holding(reason):
            if reason.activeAgentNames.isEmpty {
                return "Keeping Mac awake"
            }
            if reason.activeAgentNames == ["Manual Hold"] {
                return "Keeping Mac awake"
            }
            return "Holding for \(reason.activeAgentNames.joined(separator: ", "))"
        case let .paused(until):
            return "Paused until \(until.formatted(date: .omitted, time: .shortened))"
        case let .blocked(reason):
            return reason.displayText
        }
    }
}

public final class WakePolicyCoordinator {
    private let powerController: PowerAssertionControlling
    private let clock: Clock
    private var idleSince: Date?
    private var currentHoldReason: WakeHoldReason?

    public private(set) var status: WakeStatus = .inactive

    public init(powerController: PowerAssertionControlling, clock: Clock) {
        self.powerController = powerController
        self.clock = clock
    }

    @discardableResult
    public func update(
        settings: UserSettings,
        sessions: [AgentSession],
        battery: BatteryState
    ) -> WakeStatus {
        let now = clock.now

        guard settings.enabled else {
            releaseAndClear()
            status = .inactive
            return status
        }

        if let pauseUntil = settings.pauseUntil, pauseUntil > now {
            releaseAndClear()
            status = .paused(until: pauseUntil)
            return status
        }

        if settings.onlyWhenPluggedIn, !battery.isOnACPower {
            releaseAndClear()
            status = .blocked(.notPluggedIn)
            return status
        }

        if settings.respectLowPowerMode, battery.isLowPowerModeEnabled {
            releaseAndClear()
            status = .blocked(.lowPowerMode)
            return status
        }

        if
            let percent = battery.percent,
            percent <= settings.batteryCutoffPercent,
            !battery.isCharging,
            !battery.isOnACPower
        {
            releaseAndClear()
            status = .blocked(.batteryCutoff(percent: percent, cutoff: settings.batteryCutoffPercent))
            return status
        }

        let activeSessions = sessions.filter { $0.state == .working }
        if !activeSessions.isEmpty {
            idleSince = nil
            let activeIDs = activeSessions.map(\.id).sorted()
            let activeNames = activeSessions.map(\.displayName).sorted()
            let reason: WakeHoldReason
            if let current = currentHoldReason,
               current.activeSessionIDs == activeIDs,
               current.activeAgentNames == activeNames {
                reason = current
            } else {
                reason = WakeHoldReason(
                    activeSessionIDs: activeIDs,
                    activeAgentNames: activeNames,
                    startedAt: now,
                    note: "Manual hold is active"
                )
            }

            do {
                try powerController.acquire(
                    reason: reason,
                    preventDisplaySleep: settings.shouldPreventDisplaySleep
                )
                currentHoldReason = reason
                status = .holding(reason)
            } catch {
                releaseAndClear()
                status = .blocked(.assertionFailed(error.localizedDescription))
            }

            return status
        }

        if powerController.isHolding {
            if idleSince == nil {
                idleSince = now
            }

            let elapsed = now.timeIntervalSince(idleSince ?? now)
            if elapsed >= settings.idleReleaseDelaySeconds {
                releaseAndClear()
                status = .watching
            } else {
                let reason = currentHoldReason ?? WakeHoldReason(
                    activeSessionIDs: [],
                    activeAgentNames: [],
                    startedAt: now,
                    note: "No active session, but idle release delay has not elapsed"
                )
                status = .holding(reason)
            }
            return status
        }

        idleSince = nil
        currentHoldReason = nil
        status = .watching
        return status
    }

    private func releaseAndClear() {
        powerController.release()
        idleSince = nil
        currentHoldReason = nil
    }
}
