import LidAwakeCore
import Foundation
import IOKit

final class IOKitClamshellStateReader: ClamshellStateReading {
    func clamshellState() -> ClamshellState {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != 0 else {
            return .unavailable
        }
        defer {
            IOObjectRelease(service)
        }

        let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()

        guard let isClosed = value as? Bool else {
            return .unavailable
        }

        return isClosed ? .closed : .open
    }
}
