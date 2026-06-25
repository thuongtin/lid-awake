import SwiftUI

struct CustomPauseControl: View {
    @Binding var minutes: Int
    let compact: Bool
    let action: (Int) -> Void

    var body: some View {
        HStack(spacing: compact ? 10 : 12) {
            Label("Custom pause", systemImage: "slider.horizontal.2.square")
                .font(compact ? .caption.weight(.semibold) : .callout.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: compact ? 106 : 124, alignment: .leading)

            HStack(spacing: 6) {
                StepButton(systemImage: "minus", size: controlHeight) {
                    minutes = max(clampedMinutes - 5, 1)
                }

                TextField("min", value: sanitizedMinutes, format: .number)
                    .textFieldStyle(.plain)
                    .font(.system(size: compact ? 15 : 16, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .frame(width: compact ? 48 : 58, height: controlHeight)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.primary.opacity(0.08), lineWidth: 1)
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
                action(clampedMinutes)
            } label: {
                if compact {
                    Label("Pause", systemImage: "pause.fill")
                        .labelStyle(.iconOnly)
                } else {
                    Label("Pause", systemImage: "pause.fill")
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

    private var sanitizedMinutes: Binding<Int> {
        Binding(
            get: { clampedMinutes },
            set: { value in
                minutes = min(max(value, 1), 720)
            }
        )
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
