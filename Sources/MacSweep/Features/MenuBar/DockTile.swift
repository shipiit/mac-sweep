import AppKit
import SwiftUI

extension SettingsKeys {
    static let liveDockIcon = "liveDockIcon"
}

/// Live Dock icon: outer ring = CPU, inner ring = memory, CPU % in the middle.
/// Follows the system light/dark appearance and redraws only when a value moves by a whole percent.
@MainActor
final class DockTileController {
    private let app: AppModel
    private var loop: Task<Void, Never>?
    private var lastDrawn: (cpu: Int, memory: Int, dark: Bool)?
    private let host = NSHostingView(rootView: DockIconView(cpu: 0, memory: 0, isDark: false))

    init(app: AppModel) {
        self.app = app
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard loop == nil else { return }
            NSApp.dockTile.contentView = host
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    self?.refresh()
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        } else {
            loop?.cancel()
            loop = nil
            lastDrawn = nil
            NSApp.dockTile.contentView = nil
            NSApp.dockTile.display()
        }
    }

    private func refresh() {
        let cpu = Int((app.monitor.cpu * 100).rounded())
        let memory = app.processes.memory.map { Int((Double($0.used) / Double(max($0.total, 1)) * 100).rounded()) } ?? 0
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let last = lastDrawn, last.cpu == cpu, last.memory == memory, last.dark == dark { return }
        lastDrawn = (cpu, memory, dark)
        host.rootView = DockIconView(cpu: cpu, memory: memory, isDark: dark)
        host.frame = NSRect(origin: .zero, size: NSApp.dockTile.size)
        NSApp.dockTile.display()
    }
}

struct DockIconView: View {
    let cpu: Int
    let memory: Int
    let isDark: Bool

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * 0.80
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
                    .fill(isDark ? Color(white: 0.11) : Color.white)
                    .overlay(RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
                        .strokeBorder(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10), lineWidth: side * 0.012))
                    .frame(width: side, height: side)
                ring(value: Double(cpu) / 100, color: RingGauge.color(for: Double(cpu) / 100), diameter: side * 0.72, width: side * 0.075)
                ring(value: Double(memory) / 100, color: .purple, diameter: side * 0.50, width: side * 0.065)
                VStack(spacing: 0) {
                    Text("\(cpu)%").font(.system(size: side * 0.15, weight: .bold, design: .rounded))
                    Text("CPU").font(.system(size: side * 0.07, weight: .semibold)).opacity(0.6)
                }
                .foregroundStyle(isDark ? Color.white : Color.black)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func ring(value: Double, color: Color, diameter: CGFloat, width: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: width)
            Circle().trim(from: 0, to: min(max(value, 0.02), 1))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }
}
