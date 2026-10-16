import SwiftUI

/// Gentle opacity pulse for skeleton placeholders while content loads (solid colours only).
struct Shimmer: ViewModifier {
    @State private var dimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.45 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dimmed = true }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

/// Grey rounded bar standing in for text that hasn't loaded yet.
struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(.quaternary)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// Accent-coloured arc that spins around content while work is in progress.
struct SpinningRing: View {
    @Environment(\.appAccent) private var accent
    let isActive: Bool
    var lineWidth: CGFloat = 6
    @State private var angle: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(angle))
            .opacity(isActive ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: isActive)
            .onChange(of: isActive, initial: true) { _, active in
                guard active, !reduceMotion else { return }
                angle = 0
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { angle = 360 }
            }
            .accessibilityHidden(true)
    }
}
