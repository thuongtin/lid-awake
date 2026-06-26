import LidAwakeCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selection: SettingsPane? = .general
    @State private var customPauseMinutes = 15

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 520, idealHeight: 560)
        .animation(.snappy(duration: 0.22), value: selection)
    }

    private var sidebar: some View {
        List(SettingsPane.allCases, selection: $selection) { pane in
            Label(pane.title, systemImage: pane.systemImage)
                .tag(pane)
        }
        .listStyle(.sidebar)
        .navigationTitle("Settings")
    }

    @ViewBuilder
    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.closedLidControlNeedsAttention {
                    ClosedLidSettingsWarning(model: model)
                }

                switch selection ?? .general {
                case .general:
                    generalPane
                case .battery:
                    batteryPane
                case .behavior:
                    behaviorPane
                case .about:
                    aboutPane
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(.background)
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader(
                title: "General",
                subtitle: "Manual wake control with safety rules.",
                systemImage: "power"
            )

            StatusHero(
                title: model.settings.enabled ? "Keep Awake Is On" : "Keep Awake Is Off",
                subtitle: model.status.displayText,
                systemImage: model.settings.enabled ? "bolt.fill" : "moon.zzz.fill",
                tint: model.settings.enabled ? .green : .secondary
            ) {
                Toggle(
                    "",
                    isOn: boolBinding(\.enabled)
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }

            SettingsCard(title: "Quick Pause", systemImage: "pause.circle") {
                HStack(spacing: 10) {
                    SmoothButton("30 min", systemImage: "timer") {
                        model.pause(for: 30 * 60)
                    }

                    SmoothButton("1 hour", systemImage: "clock") {
                        model.pause(for: 60 * 60)
                    }

                    SmoothButton("Clear", systemImage: "play.circle") {
                        model.clearPause()
                    }
                    .disabled(model.settings.pauseUntil == nil)
                }

                Divider()

                CustomPauseControl(
                    minutes: $customPauseMinutes,
                    compact: false
                ) { minutes in
                    model.pause(for: TimeInterval(minutes * 60))
                }

                if let pauseUntil = model.settings.pauseUntil {
                    Divider()
                    InfoLine(
                        title: "Paused until",
                        value: pauseUntil.formatted(date: .omitted, time: .shortened),
                        systemImage: "clock.badge"
                    )
                    .contentTransition(.numericText())
                }
            }

            SettingsCard(title: "Startup", systemImage: "arrow.clockwise.circle") {
                ToggleRow(
                    title: "Launch at login",
                    subtitle: "Start Lid Awake when you sign in.",
                    systemImage: "restart.circle",
                    isOn: launchAtLoginBinding
                )

                if let error = model.launchAtLoginError {
                    Divider()
                    InfoLine(
                        title: "Login item error",
                        value: error,
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
        }
    }

    private var batteryPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader(
                title: "Battery",
                subtitle: "Stop holding before power gets risky.",
                systemImage: model.battery.isCharging ? "powerplug.fill" : "battery.75percent"
            )

            SettingsCard(title: "Power Source", systemImage: "powerplug") {
                ToggleRow(
                    title: "Only while plugged in",
                    subtitle: "Release wake assertions on battery power.",
                    systemImage: "powerplug.fill",
                    isOn: boolBinding(\.onlyWhenPluggedIn)
                )

                Divider()

                ToggleRow(
                    title: "Respect Low Power Mode",
                    subtitle: "Let macOS battery policy take priority.",
                    systemImage: "leaf.fill",
                    isOn: boolBinding(\.respectLowPowerMode)
                )
            }

            SettingsCard(title: "Battery Cutoff", systemImage: "battery.25percent") {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(model.settings.batteryCutoffPercent)%")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())

                    Text("minimum battery")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                Slider(
                    value: batteryCutoffBinding,
                    in: 5...80,
                    step: 5
                )
                .controlSize(.large)

                InfoLine(
                    title: "Current battery",
                    value: batterySummary,
                    systemImage: currentBatteryIcon
                )
            }
        }
    }

    private var behaviorPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader(
                title: "Behavior",
                subtitle: "Tune lid behavior and wake assertions.",
                systemImage: "slider.horizontal.3"
            )

            SettingsCard(title: "Wake Assertions", systemImage: "bolt.circle") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("When lid closes")
                        .font(.callout.weight(.medium))

                    Picker("When lid closes", selection: lidClosedDisplayModeBinding) {
                        ForEach(LidClosedDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.displayName)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(model.settings.lidClosedDisplayMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Divider()

                    ToggleRow(
                        title: "Lock Mac when lid closes",
                        subtitle: "Switch to the lock screen once per lid closure.",
                        systemImage: "lock.fill",
                        isOn: boolBinding(\.lockScreenWhenLidCloses)
                    )

                    Divider()

                    InfoLine(
                        title: "System closed-lid mode",
                        value: model.closedLidStatus.displayText,
                        systemImage: "laptopcomputer"
                    )

                    InfoLine(
                        title: "Advanced Helper",
                        value: model.closedLidHelperStatus.displayText,
                        systemImage: "lock.shield"
                    )

                    HStack(spacing: 10) {
                        SmoothButton("Set Up", systemImage: "lock.shield") {
                            model.setupClosedLidHelper()
                        }
                        .disabled(model.closedLidHelperStatus == .enabled)

                        SmoothButton("Remove", systemImage: "trash") {
                            model.removeClosedLidHelper()
                        }
                        .disabled(model.closedLidHelperStatus == .notRegistered)
                    }

                    if model.isChangingClosedLidMode {
                        InfoLine(
                            title: "Helper update",
                            value: "Updating helper",
                            systemImage: "lock.shield"
                        )
                    }

                    if let error = model.closedLidError {
                        InfoLine(
                            title: "Closed-lid error",
                            value: error,
                            systemImage: "exclamationmark.triangle"
                        )
                    }

                    if let error = model.closedLidDisplayError {
                        InfoLine(
                            title: "Display sleep error",
                            value: error,
                            systemImage: "display.trianglebadge.exclamationmark"
                        )
                    }

                    if let error = model.closedLidLockError {
                        InfoLine(
                            title: "Screen lock error",
                            value: error,
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                }
            }
        }
    }

    private var aboutPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader(
                title: "Safety",
                subtitle: "Transparent limits for a native macOS utility.",
                systemImage: "shield.checkered"
            )

            SettingsCard(title: "What Lid Awake Does", systemImage: "checkmark.seal") {
                InfoLine(
                    title: "Wake method",
                    value: "Idle assertions plus optional closed-lid mode",
                    systemImage: "bolt"
                )
                Divider()
                InfoLine(
                    title: "Closed lid",
                    value: "Uses admin-approved pmset when enabled",
                    systemImage: "laptopcomputer"
                )
                Divider()
                InfoLine(
                    title: "System settings",
                    value: "Changed only when keep-display-on is selected",
                    systemImage: "gearshape"
                )
            }
        }
    }

    private var batterySummary: String {
        guard let percent = model.battery.percent else {
            if model.battery.isCharging {
                return "Charging"
            }
            return model.battery.isLowPowerModeEnabled ? "Unknown, Low Power Mode" : "Desktop or unknown"
        }

        if model.battery.isCharging {
            return "\(percent)% Charging"
        }

        if model.battery.isOnACPower {
            return "\(percent)% AC Power"
        }

        return "\(percent)% Battery"
    }

    private var currentBatteryIcon: String {
        if model.battery.isCharging {
            return "bolt.fill"
        }

        if model.battery.isLowPowerModeEnabled {
            return "leaf.fill"
        }

        return model.battery.isOnACPower ? "powerplug.fill" : "battery.100percent"
    }

    private var batteryCutoffBinding: Binding<Double> {
        Binding(
            get: { Double(model.settings.batteryCutoffPercent) },
            set: { value in
                model.updateSettings { settings in
                    settings.batteryCutoffPercent = Int(value.rounded())
                }
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.settings.launchAtLogin },
            set: { value in
                model.updateLaunchAtLogin(value)
            }
        )
    }

    private var lidClosedDisplayModeBinding: Binding<LidClosedDisplayMode> {
        Binding(
            get: { model.settings.lidClosedDisplayMode },
            set: { value in
                model.updateLidClosedDisplayMode(value)
            }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<UserSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in
                model.updateSettings { settings in
                    settings[keyPath: keyPath] = value
                }
            }
        )
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case battery
    case behavior
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            "General"
        case .battery:
            "Battery"
        case .behavior:
            "Behavior"
        case .about:
            "Safety"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "power"
        case .battery:
            "battery.75percent"
        case .behavior:
            "slider.horizontal.3"
        case .about:
            "shield.checkered"
        }
    }
}

private struct PaneHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.weight(.semibold))

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct StatusHero<Accessory: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 54, height: 54)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
            accessory
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct ClosedLidSettingsWarning: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.20))
                .frame(width: 48, height: 48)
                .background(Color(red: 0.36, green: 0.19, blue: 0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(model.closedLidAttentionTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(model.closedLidAttentionMessage)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        model.setupClosedLidHelper()
                    } label: {
                        Label(model.closedLidPrimaryActionTitle, systemImage: "lock.shield")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Color(red: 1.0, green: 0.68, blue: 0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.openClosedLidApprovalSettings()
                    } label: {
                        Label("Open System Settings", systemImage: "gearshape")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(red: 0.16, green: 0.09, blue: 0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(red: 0.95, green: 0.48, blue: 0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)

            content
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private struct InfoLine: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            Text(title)
                .font(.callout)

            Spacer()

            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct SmoothButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
