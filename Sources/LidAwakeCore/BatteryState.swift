import Foundation

public struct BatteryState: Equatable, Sendable {
    public var percent: Int?
    public var isCharging: Bool
    public var isOnACPower: Bool
    public var isLowPowerModeEnabled: Bool

    public init(
        percent: Int?,
        isCharging: Bool,
        isOnACPower: Bool,
        isLowPowerModeEnabled: Bool
    ) {
        self.percent = percent
        self.isCharging = isCharging
        self.isOnACPower = isOnACPower
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }

    public static func desktopOrUnknown(lowPowerMode: Bool) -> BatteryState {
        BatteryState(
            percent: nil,
            isCharging: false,
            isOnACPower: true,
            isLowPowerModeEnabled: lowPowerMode
        )
    }
}
