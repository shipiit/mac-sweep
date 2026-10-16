import SwiftUI

/// Minimal area sparkline for 0...1 values, newest on the right.
struct Sparkline: View {
    @Environment(\.appAccent) private var accent
    let values: [Double]
    var color: Color? = nil
    var capacity = 60

    var body: some View {
        let color = self.color ?? accent
        GeometryReader { proxy in
            let points = points(in: proxy.size)
            ZStack {
                if let first = points.first, let last = points.last {
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: last.x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(color.opacity(0.15))
                    Path { path in path.addLines(points) }
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Recent usage, now \(Int(((values.last ?? 0) * 100).rounded())) percent")
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = size.width / CGFloat(max(capacity - 1, 1))
        let offset = size.width - step * CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(x: offset + CGFloat(index) * step, y: size.height * (1 - CGFloat(min(max(value, 0), 1))))
        }
    }
}
