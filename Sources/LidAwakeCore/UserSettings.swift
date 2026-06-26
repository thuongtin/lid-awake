import Foundation

public enum LidClosedDisplayMode: String, CaseIterable, Codable, Equatable, Sendable {
    case turnDisplayOff
    case keepDisplayOn

    public var displayName: String {
        switch self {
        case .turnDisplayOff:
            "Turn display off"
        case .keepDisplayOn:
            "Keep display on"
        }
    }

    public var description: String {
        switch self {
        case .turnDisplayOff:
            "Keep running after the lid closes and let the display sleep."
        case .keepDisplayOn:
            "Keep running after the lid closes and keep the display awake."
        }
    }
}

public struct UserSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var launchAtLogin: Bool
    public var batteryCutoffPercent: Int
    public var onlyWhenPluggedIn: Bool
    public var respectLowPowerMode: Bool
    public var idleReleaseDelaySeconds: TimeInterval
    public var preventDisplaySleep: Bool
    public var lidClosedDisplayMode: LidClosedDisplayMode
    public var lockScreenWhenLidCloses: Bool
    public var pauseUntil: Date?

    public init(
        enabled: Bool = true,
        launchAtLogin: Bool = false,
        batteryCutoffPercent: Int = 20,
        onlyWhenPluggedIn: Bool = false,
        respectLowPowerMode: Bool = true,
        idleReleaseDelaySeconds: TimeInterval = 30,
        preventDisplaySleep: Bool = true,
        lidClosedDisplayMode: LidClosedDisplayMode = .turnDisplayOff,
        lockScreenWhenLidCloses: Bool = false,
        pauseUntil: Date? = nil
    ) {
        self.enabled = enabled
        self.launchAtLogin = launchAtLogin
        self.batteryCutoffPercent = batteryCutoffPercent
        self.onlyWhenPluggedIn = onlyWhenPluggedIn
        self.respectLowPowerMode = respectLowPowerMode
        self.idleReleaseDelaySeconds = idleReleaseDelaySeconds
        self.preventDisplaySleep = preventDisplaySleep
        self.lidClosedDisplayMode = lidClosedDisplayMode
        self.lockScreenWhenLidCloses = lockScreenWhenLidCloses
        self.pauseUntil = pauseUntil
    }

    public static let defaults = UserSettings()

    public var shouldPreventDisplaySleep: Bool {
        preventDisplaySleep && lidClosedDisplayMode == .keepDisplayOn
    }

    public var shouldPreventClosedLidSleep: Bool {
        true
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case launchAtLogin
        case batteryCutoffPercent
        case onlyWhenPluggedIn
        case respectLowPowerMode
        case idleReleaseDelaySeconds
        case preventDisplaySleep
        case lidClosedDisplayMode
        case lockScreenWhenLidCloses
        case pauseUntil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.batteryCutoffPercent = try container.decodeIfPresent(Int.self, forKey: .batteryCutoffPercent) ?? 20
        self.onlyWhenPluggedIn = try container.decodeIfPresent(Bool.self, forKey: .onlyWhenPluggedIn) ?? false
        self.respectLowPowerMode = try container.decodeIfPresent(Bool.self, forKey: .respectLowPowerMode) ?? true
        self.idleReleaseDelaySeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .idleReleaseDelaySeconds) ?? 30
        self.preventDisplaySleep = try container.decodeIfPresent(Bool.self, forKey: .preventDisplaySleep) ?? true
        self.lidClosedDisplayMode = try container.decodeIfPresent(
            LidClosedDisplayMode.self,
            forKey: .lidClosedDisplayMode
        ) ?? .turnDisplayOff
        self.lockScreenWhenLidCloses = try container.decodeIfPresent(
            Bool.self,
            forKey: .lockScreenWhenLidCloses
        ) ?? false
        self.pauseUntil = try container.decodeIfPresent(Date.self, forKey: .pauseUntil)
    }
}
