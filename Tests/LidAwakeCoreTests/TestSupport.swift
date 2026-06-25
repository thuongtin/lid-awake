import LidAwakeCore
import Foundation

final class FakeClock: Clock {
    var now: Date

    init(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        self.now = now
    }

    func advance(seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

final class FakePowerController: PowerAssertionControlling {
    var isHolding = false
    var acquireCount = 0
    var releaseCount = 0
    var lastPreventDisplaySleep = false
    var failAcquire = false

    func acquire(reason: WakeHoldReason, preventDisplaySleep: Bool) throws {
        if failAcquire {
            throw NSError(domain: "FakePowerController", code: 1)
        }

        lastPreventDisplaySleep = preventDisplaySleep
        if !isHolding {
            acquireCount += 1
            isHolding = true
        }
    }

    func release() {
        if isHolding {
            releaseCount += 1
        }
        isHolding = false
    }
}

func session(
    id: String = "session-1",
    kind: AgentKind = .codexCli,
    state: AgentState = .working,
    date: Date = Date(timeIntervalSince1970: 1_800_000_000)
) -> AgentSession {
    AgentSession(
        id: id,
        kind: kind,
        displayName: kind.displayName,
        state: state,
        source: .lifecycleHook,
        lastEventAt: date
    )
}
