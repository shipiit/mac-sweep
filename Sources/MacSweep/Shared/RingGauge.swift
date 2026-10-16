import SwiftUI

struct RingGauge: View {
    let value: Double
    let label: String
    var caption: String? = nil
    var size: CGFloat = 54
    var lineWidth: CGFloat = 6
    /// For "higher is better" values such as a score.
    var invertColors = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: min(max(value, 0), 1))
                    .stroke(Self.color(for: invertColors ? 1 - value : value), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: size * 0.24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: size, height: size)
            Text(label).font(.caption.weight(.medium))
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(Int((value * 100).rounded())) percent")
    }

    static func color(for value: Double) -> Color {
        switch value {
        case ..<0.6: .green
        case ..<0.85: .orange
        default: .red
        }
    }
}

/// First click arms the button, second click within a few seconds performs the action.
/// Used where a modal confirmation would be awkward (menu bar panel, notch).
struct InlineConfirmButton: View {
    let help: String
    let action: () -> Void
    @State private var isArmed = false

    var body: some View {
        Button {
            if isArmed {
                action()
                isArmed = false
            } else {
                withAnimation(.snappy) { isArmed = true }
            }
        } label: {
            if isArmed {
                Text("Quit?").font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.red, in: Capsule())
            } else {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(isArmed ? "Confirm: \(help)" : help)
        .task(id: isArmed) {
            guard isArmed else { return }
            try? await Task.sleep(for: .seconds(3))
            withAnimation { isArmed = false }
        }
    }
}
