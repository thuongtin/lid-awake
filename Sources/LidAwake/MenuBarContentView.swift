import LidAwakeCore
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void
    @State private var customPauseMinutes = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusPanel
            if model.closedLidControlNeedsAttention {
                closedLidWarningPanel
            }
            metricsPanel
            quickActionsPanel
            footerActions
        }
        .padding(14)
        .frame(width: 360)
        .animation(.snappy(duration: 0.22), value: model.status)
        .animation(.snappy(duration: 0.22), value: model.settings)
        .animation(.snappy(duration: 0.22), value: model.battery)
        .animation(.snappy(duration: 0.22), value: model.closedLidHelperStatus)
        .onAppear {
            DispatchQueue.main.async {
                model.refreshAfterExternalPermissionChange()
            }
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                StatusGlyph(systemImage: statusIcon, tint: statusColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Lid Awake")
                        .font(.headline.weight(.semibold))

                    Text(model.status.displayText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                StatusBadge(
                    title: statusBadgeTitle,
                    systemImage: statusBadgeIcon,
                    tint: statusColor
                )
            }

            HStack(spacing: 10) {
                Label("Keep awake", systemImage: model.settings.enabled ? "bolt.fill" : "moon.zzz.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { model.settings.enabled },
                        set: { value in
                            model.updateSettings { $0.enabled = value }
                        }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var metricsPanel: some View {
        VStack(spacing: 10) {
            batteryRow

            MetricTile(
                title: "Lid",
                value: lidModeTitle,
                detail: model.closedLidStatus.displayText,
                systemImage: lidModeIcon,
                tint: lidModeColor
            )
        }
    }

    private var closedLidWarningPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.20))
                    .frame(width: 34, height: 34)
                    .background(Color(red: 0.36, green: 0.19, blue: 0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.closedLidAttentionTitle)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    Text(model.closedLidMenuAttentionMessage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                Button {
                    model.setupClosedLidHelper()
                } label: {
                    Label(model.closedLidCompactActionTitle, systemImage: "lock.shield")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color(red: 1.0, green: 0.68, blue: 0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(red: 0.16, green: 0.09, blue: 0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(red: 0.95, green: 0.48, blue: 0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private var batteryRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: batteryIcon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(batteryColor)
                    .frame(width: 30, height: 30)
                    .background(batteryColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Power")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(batteryTitle)
                        .font(.callout.weight(.medium))
                        .contentTransition(.numericText())
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    PowerStateBadge(
                        title: powerBadgeTitle,
                        systemImage: powerBadgeIcon,
                        tint: batteryColor
                    )

                    Text("Cutoff \(model.settings.batteryCutoffPercent)%")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let percent = model.battery.percent {
                ProgressView(value: Double(percent), total: 100)
                    .tint(batteryColor)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var quickActionsPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                IconActionButton("30 min", systemImage: "timer") {
                    model.pause(for: 30 * 60)
                }

                IconActionButton("1 hour", systemImage: "clock") {
                    model.pause(for: 60 * 60)
                }

                IconActionButton("Clear", systemImage: "play.circle") {
                    model.clearPause()
                }
                .disabled(model.settings.pauseUntil == nil)
            }

            CustomPauseControl(
                minutes: $customPauseMinutes,
                compact: true
            ) { minutes in
                model.pause(for: TimeInterval(minutes * 60))
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: 10) {
            FooterButton("Settings", systemImage: "gearshape") {
                openSettings()
            }

            FooterButton("Quit", systemImage: "power") {
                model.quit()
            }
            .keyboardShortcut("q")
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .holding:
            .green
        case .blocked:
            .orange
        case .paused:
            .yellow
        case .inactive:
            .secondary
        case .watching:
            .blue
        }
    }

    private var statusIcon: String {
        switch model.status {
        case .holding:
            "bolt.fill"
        case .blocked:
            "exclamationmark.triangle.fill"
        case .paused:
            "pause.fill"
        case .inactive:
            "moon.zzz.fill"
        case .watching:
            "bolt.circle"
        }
    }

    private var statusBadgeTitle: String {
        switch model.status {
        case .holding:
            "On"
        case .blocked:
            "Blocked"
        case .paused:
            "Paused"
        case .inactive:
            "Off"
        case .watching:
            "Ready"
        }
    }

    private var statusBadgeIcon: String {
        switch model.status {
        case .holding:
            "checkmark.circle.fill"
        case .blocked:
            "exclamationmark.circle.fill"
        case .paused:
            "pause.circle.fill"
        case .inactive:
            "power.circle"
        case .watching:
            "circle.dotted"
        }
    }

    private var batteryTitle: String {
        guard let percent = model.battery.percent else {
            if model.battery.isCharging {
                return "Charging"
            }
            return model.battery.isLowPowerModeEnabled ? "Unknown, Low Power" : "Desktop or unknown"
        }

        if model.battery.isCharging {
            return "\(percent)% Charging"
        }

        if model.battery.isOnACPower {
            return "\(percent)% AC Power"
        }

        return "\(percent)% Battery"
    }

    private var batteryIcon: String {
        guard let percent = model.battery.percent else {
            return model.battery.isLowPowerModeEnabled ? "leaf.fill" : "desktopcomputer"
        }

        if model.battery.isCharging {
            return "powerplug.fill"
        }

        if percent <= model.settings.batteryCutoffPercent {
            return "battery.25percent"
        }

        return "battery.75percent"
    }

    private var batteryColor: Color {
        if model.battery.isLowPowerModeEnabled {
            return .mint
        }

        guard let percent = model.battery.percent else {
            return .secondary
        }

        if percent <= model.settings.batteryCutoffPercent {
            return .orange
        }

        return model.battery.isOnACPower ? .green : .blue
    }

    private var powerBadgeTitle: String {
        if model.battery.isCharging {
            return "Charging"
        }

        if model.battery.isLowPowerModeEnabled {
            return "Low Power"
        }

        return model.battery.isOnACPower ? "AC" : "Battery"
    }

    private var powerBadgeIcon: String {
        if model.battery.isCharging {
            return "bolt.fill"
        }

        if model.battery.isLowPowerModeEnabled {
            return "leaf.fill"
        }

        return model.battery.isOnACPower ? "powerplug.fill" : "battery.75percent"
    }

    private var lidModeTitle: String {
        switch model.settings.lidClosedDisplayMode {
        case .turnDisplayOff:
            "Display Off"
        case .keepDisplayOn:
            "Display On"
        }
    }

    private var lidModeIcon: String {
        switch model.settings.lidClosedDisplayMode {
        case .turnDisplayOff:
            "moon.zzz.fill"
        case .keepDisplayOn:
            "display"
        }
    }

    private var lidModeColor: Color {
        switch model.settings.lidClosedDisplayMode {
        case .turnDisplayOff:
            .secondary
        case .keepDisplayOn:
            .purple
        }
    }
}

private struct StatusGlyph: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 25, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: 48, height: 48)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct StatusBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct PowerStateBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct IconActionButton: View {
    @Environment(\.isEnabled) private var isEnabled

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
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))

                Text(title)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isEnabled ? Color.primary.opacity(0.12) : Color.clear, lineWidth: 1)
        }
        .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct FooterButton: View {
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
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}
