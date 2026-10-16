import AppKit

/// Draws the menu bar item: MacSweep's ring-and-sparkle mark plus two stacked readings.
/// Rendered as a template image so macOS tints it correctly for light, dark and tinted menu bars.
enum MenuBarGlyph {
    static func image(cpu: Double, memory: Double, style: MenuBarStyle = .cpuAndMemory) -> NSImage {
        let top = style == .iconOnly ? "" : "CPU \(percent(cpu))"
        let bottom = style == .cpuAndMemory ? "MEM \(percent(memory))" : ""
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textWidth = max((top as NSString).size(withAttributes: attributes).width, (bottom as NSString).size(withAttributes: attributes).width)
        let size = NSSize(width: style == .iconOnly ? 18 : 18 + 4 + ceil(textWidth), height: 22)

        let image = NSImage(size: size, flipped: false) { _ in
            drawMark(in: NSRect(x: 0, y: 3, width: 16, height: 16))
            (top as NSString).draw(at: NSPoint(x: 22, y: style == .cpuOnly ? 6 : 11), withAttributes: attributes)
            (bottom as NSString).draw(at: NSPoint(x: 22, y: 1.5), withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MacSweep: CPU \(percent(cpu)), memory \(percent(memory))"
        return image
    }

    static func percent(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }

    /// Mini version of the app icon: a 270° gauge ring around a four-point sparkle.
    static func drawMark(in rect: NSRect) {
        NSColor.black.set()
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let ring = NSBezierPath()
        ring.appendArc(withCenter: center, radius: rect.width / 2 - 1.2, startAngle: 90, endAngle: -180, clockwise: true)
        ring.lineWidth = 2
        ring.lineCapStyle = .round
        ring.stroke()

        let r = rect.width * 0.24
        let waist = r * 0.25
        let sparkle = NSBezierPath()
        sparkle.move(to: NSPoint(x: center.x, y: center.y + r))
        sparkle.line(to: NSPoint(x: center.x + waist, y: center.y + waist))
        sparkle.line(to: NSPoint(x: center.x + r, y: center.y))
        sparkle.line(to: NSPoint(x: center.x + waist, y: center.y - waist))
        sparkle.line(to: NSPoint(x: center.x, y: center.y - r))
        sparkle.line(to: NSPoint(x: center.x - waist, y: center.y - waist))
        sparkle.line(to: NSPoint(x: center.x - r, y: center.y))
        sparkle.line(to: NSPoint(x: center.x - waist, y: center.y + waist))
        sparkle.close()
        sparkle.fill()
    }
}
