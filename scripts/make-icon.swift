// Renders the app icon PNGs into the iconset directory given as the first argument.
// Design: indigo→cyan squircle, a white gauge ring (disk/health), and a sparkle (clean).
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data? {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext

    // Apple's macOS grid: 824/1024 body, centred, with a soft drop shadow.
    let body = size * 824 / 1024
    let tile = NSRect(x: (size - body) / 2, y: (size - body) / 2 + size * 0.01, width: body, height: body)
    let shape = NSBezierPath(roundedRect: tile, xRadius: body * 0.2237, yRadius: body * 0.2237)

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill()
    shape.fill()
    cg.restoreGState()

    NSGradient(colors: [
        NSColor(red: 0.36, green: 0.30, blue: 0.98, alpha: 1),
        NSColor(red: 0.20, green: 0.52, blue: 0.98, alpha: 1),
        NSColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1),
    ])?.draw(in: shape, angle: -55)

    // Glassy highlight across the top half.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])?
        .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Gauge ring: faint track plus a bright 270° arc.
    let center = CGPoint(x: tile.midX, y: tile.midY)
    let radius = body * 0.29
    let lineWidth = body * 0.085
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = lineWidth
    NSColor.white.withAlphaComponent(0.22).setStroke()
    track.stroke()

    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: -180, clockwise: true)
    arc.lineWidth = lineWidth
    arc.lineCapStyle = .round
    NSColor.white.setStroke()
    arc.stroke()

    // Four-point sparkle in the middle.
    let sparkle = NSBezierPath()
    let r = body * 0.15
    let waist = r * 0.22
    sparkle.move(to: CGPoint(x: center.x, y: center.y + r))
    sparkle.curve(to: CGPoint(x: center.x + r, y: center.y), controlPoint1: CGPoint(x: center.x + waist, y: center.y + waist),
                  controlPoint2: CGPoint(x: center.x + waist, y: center.y + waist))
    sparkle.curve(to: CGPoint(x: center.x, y: center.y - r), controlPoint1: CGPoint(x: center.x + waist, y: center.y - waist),
                  controlPoint2: CGPoint(x: center.x + waist, y: center.y - waist))
    sparkle.curve(to: CGPoint(x: center.x - r, y: center.y), controlPoint1: CGPoint(x: center.x - waist, y: center.y - waist),
                  controlPoint2: CGPoint(x: center.x - waist, y: center.y - waist))
    sparkle.curve(to: CGPoint(x: center.x, y: center.y + r), controlPoint1: CGPoint(x: center.x - waist, y: center.y + waist),
                  controlPoint2: CGPoint(x: center.x - waist, y: center.y + waist))
    sparkle.close()
    NSColor.white.setFill()
    sparkle.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try render(base * scale)?.write(to: output.appendingPathComponent(name))
    }
}
