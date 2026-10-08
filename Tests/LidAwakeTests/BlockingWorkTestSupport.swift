@testable import LidAwake
import Foundation

/// Runs the work at once, like a queue that is never busy, but still delivers
/// on a later main-queue turn, the way the real one does.
struct DeferredBlockingWork: BlockingWorkPerforming {
    func perform<Value>(_ work: @escaping () -> Value, then deliver: @escaping @MainActor (Value) -> Void) {
        let value = work()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                deliver(value)
            }
        }
    }
}

/// Holds work until the test releases it, to look at the state in between.
final class HeldBlockingWork: BlockingWorkPerforming {
    private var held: [() -> Void] = []

    var pendingCount: Int {
        held.count
    }

    func perform<Value>(_ work: @escaping () -> Value, then deliver: @escaping @MainActor (Value) -> Void) {
        held.append {
            let value = work()
            MainActor.assumeIsolated {
                deliver(value)
            }
        }
    }

    func releaseAll() {
        let work = held
        held = []
        work.forEach { $0() }
    }
}
