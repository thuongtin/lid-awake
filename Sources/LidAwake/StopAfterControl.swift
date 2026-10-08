import SwiftUI

struct StopAfterControl: View {
    @Binding var minutes: Int
    let compact: Bool
    let action: (Int) -> Void

    /// What the field shows. A number field only hands its value over on
    /// Return or focus loss, so pressing Stop right after typing used the old
    /// number. Reading the text as it is typed avoids that.
    @State private var text = ""

    var body: some View {
        HStack(spacing: compact ? 10 : 12) {
            Label("Custom time", systemImage: "slider.horizontal.2.square")
                .font(compact ? .caption.weight(.semibold) : .callout.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: compact ? 106 : 124, alignment: .leading)

            HStack(spacing: 6) {
                StepButton(systemImage: "minus", size: controlHeight) {
                    minutes = max(clampedMinutes - 5, 1)
                }

                TextField("min", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: compact ? 15 : 16, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .frame(width: compact ? 48 : 58, height: controlHeight)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.primary.opacity(0.08), lineWidth: 1)
                    }
                    .onAppear {
                        text = String(clampedMinutes)
                    }
                    .onChange(of: minutes) { _, _ in
                        if Self.minutes(fromTyped: text) != clampedMinutes {
                            text = String(clampedMinutes)
                        }
                    }
                    .onChange(of: text) { _, newText in
                        if let typed = Self.minutes(fromTyped: newText) {
                            minutes = typed
                        }
                    }
                    .onSubmit {
                        text = String(clampedMinutes)
                    }

                StepButton(systemImage: "plus", size: controlHeight) {
                    minutes = min(clampedMinutes + 5, 720)
                }
            }
            .frame(width: compact ? 120 : 140)

            Text("min")
                .font(compact ? .caption.weight(.medium) : .callout)
                .foregroundStyle(.secondary)
                .frame(width: compact ? 25 : 31, alignment: .leading)

            Button {
                let chosen = Self.minutes(fromTyped: text) ?? clampedMinutes
                minutes = chosen
                text = String(chosen)
                action(chosen)
            } label: {
                if compact {
                    Label("Stop", systemImage: "stop.fill")
                        .labelStyle(.iconOnly)
                } else {
                    Label("Stop", systemImage: "stop.fill")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: compact ? 13 : 14, weight: .semibold))
            .frame(width: compact ? controlHeight : 92, height: controlHeight)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            }
            .disabled(clampedMinutes <= 0)
        }
    }

    /// The minutes typed so far, clamped to what the control allows, or nil
    /// while the text holds no number yet.
    static func minutes(fromTyped text: String) -> Int? {
        let digits = text.filter(\.isWholeNumber)
        guard !digits.isEmpty else {
            return nil
        }
        guard let value = Int(digits) else {
            return 720
        }
        return min(max(value, 1), 720)
    }

    private var clampedMinutes: Int {
        min(max(minutes, 1), 720)
    }

    private var controlHeight: CGFloat {
        compact ? 34 : 36
    }
}

private struct StepButton: View {
    let systemImage: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .frame(width: size, height: size)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
