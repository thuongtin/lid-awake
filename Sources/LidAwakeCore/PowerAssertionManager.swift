import Foundation

public enum PowerAssertionType: Hashable, Sendable {
    case preventUserIdleSystemSleep
    case preventUserIdleDisplaySleep
}

public enum PowerAssertionError: Error, Equatable {
    case createFailed(type: PowerAssertionType, code: Int32)
}

extension PowerAssertionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .createFailed(type, code):
            "Failed to create \(type) assertion with code \(code)"
        }
    }
}

public protocol PowerAssertionCreating: AnyObject {
    func createAssertion(type: PowerAssertionType, reason: String) throws -> UInt32
    func releaseAssertion(id: UInt32)
}

public protocol PowerAssertionControlling: AnyObject {
    var isHolding: Bool { get }
    func acquire(reason: WakeHoldReason, preventDisplaySleep: Bool) throws
    func release()
}

public final class PowerAssertionManager: PowerAssertionControlling {
    private let creator: PowerAssertionCreating
    private var systemAssertionID: UInt32?
    private var displayAssertionID: UInt32?

    public init(creator: PowerAssertionCreating) {
        self.creator = creator
    }

    public var isHolding: Bool {
        systemAssertionID != nil || displayAssertionID != nil
    }

    public func acquire(reason: WakeHoldReason, preventDisplaySleep: Bool) throws {
        if systemAssertionID != nil {
            try reconcileDisplayAssertion(reason: reason, preventDisplaySleep: preventDisplaySleep)
            return
        }

        let reasonText = reason.assertionReason
        let systemID = try creator.createAssertion(
            type: .preventUserIdleSystemSleep,
            reason: reasonText
        )

        do {
            var displayID: UInt32?
            if preventDisplaySleep {
                displayID = try creator.createAssertion(
                    type: .preventUserIdleDisplaySleep,
                    reason: reasonText
                )
            }

            systemAssertionID = systemID
            displayAssertionID = displayID
        } catch {
            creator.releaseAssertion(id: systemID)
            throw error
        }
    }

    private func reconcileDisplayAssertion(reason: WakeHoldReason, preventDisplaySleep: Bool) throws {
        if preventDisplaySleep {
            guard displayAssertionID == nil else {
                return
            }

            displayAssertionID = try creator.createAssertion(
                type: .preventUserIdleDisplaySleep,
                reason: reason.assertionReason
            )
            return
        }

        if let displayAssertionID {
            creator.releaseAssertion(id: displayAssertionID)
            self.displayAssertionID = nil
        }
    }

    public func release() {
        if let displayAssertionID {
            creator.releaseAssertion(id: displayAssertionID)
        }

        if let systemAssertionID {
            creator.releaseAssertion(id: systemAssertionID)
        }

        displayAssertionID = nil
        systemAssertionID = nil
    }
}
