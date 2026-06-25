import LidAwakeCore
import Foundation
import IOKit
import IOKit.pwr_mgt
import OSLog

final class IOKitPowerAssertionCreator: PowerAssertionCreating {
    private let logger = Logger(subsystem: "com.thuongtin.LidAwake", category: "power")

    func createAssertion(type: PowerAssertionType, reason: String) throws -> UInt32 {
        var assertionID = IOPMAssertionID(0)
        let assertionType: CFString

        switch type {
        case .preventUserIdleSystemSleep:
            assertionType = kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        case .preventUserIdleDisplaySleep:
            assertionType = kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        }

        let result = IOPMAssertionCreateWithName(
            assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )

        guard result == kIOReturnSuccess else {
            logger.error("create assertion failed type=\(String(describing: type), privacy: .public) code=\(Int32(result))")
            throw PowerAssertionError.createFailed(type: type, code: Int32(result))
        }

        logger.info("created assertion type=\(String(describing: type), privacy: .public) id=\(assertionID)")
        return assertionID
    }

    func releaseAssertion(id: UInt32) {
        logger.info("released assertion id=\(id)")
        IOPMAssertionRelease(IOPMAssertionID(id))
    }
}
