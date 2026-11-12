import Foundation

/// Runs work that can block on another process, such as a `pmset` read, away
/// from the main actor, then hands the result back on the main queue.
protocol BlockingWorkPerforming {
    func perform<Value>(_ work: @escaping () -> Value, then deliver: @escaping @MainActor (Value) -> Void)
}

/// One serial queue, so results come back in the order the work was asked for.
struct BackgroundBlockingWork: BlockingWorkPerforming {
    private let queue: DispatchQueue

    init(label: String = "com.thuongtin.LidAwake.blocking-work") {
        queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    func perform<Value>(_ work: @escaping () -> Value, then deliver: @escaping @MainActor (Value) -> Void) {
        queue.async {
            let value = work()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    deliver(value)
                }
            }
        }
    }
}
