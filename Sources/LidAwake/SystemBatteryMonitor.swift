import LidAwakeCore
import Foundation
import IOKit.ps

final class SystemBatteryMonitor {
    func currentState() -> BatteryState {
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .desktopOrUnknown(lowPowerMode: lowPowerMode)
        }

        guard let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return .desktopOrUnknown(lowPowerMode: lowPowerMode)
        }

        for source in sources {
            guard
                let rawDescription = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue(),
                let description = rawDescription as? [String: Any]
            else {
                continue
            }

            let type = description[kIOPSTypeKey] as? String
            if type != nil, type != kIOPSInternalBatteryType {
                continue
            }

            let current = description[kIOPSCurrentCapacityKey] as? Int
            let max = description[kIOPSMaxCapacityKey] as? Int
            let percent: Int?
            if let current, let max, max > 0 {
                percent = Int((Double(current) / Double(max) * 100).rounded())
            } else {
                percent = nil
            }

            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let powerState = description[kIOPSPowerSourceStateKey] as? String
            let isOnACPower = powerState == kIOPSACPowerValue

            return BatteryState(
                percent: percent,
                isCharging: isCharging,
                isOnACPower: isOnACPower,
                isLowPowerModeEnabled: lowPowerMode
            )
        }

        return .desktopOrUnknown(lowPowerMode: lowPowerMode)
    }
}
