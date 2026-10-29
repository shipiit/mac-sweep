import MacSweepCore
import SwiftUI

/// One app: icon, total footprint, a stacked bar scaled to the largest app, and the two actions.
struct AppFootprintRow: View {
    let footprint: AppFootprint
    /// Total of the largest app, so bar lengths compare across rows.
    let scale: UInt64
    let isRunning: Bool
    let isWorking: Bool
    let onClearCache: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FileIcon(path: footprint.app.path, size: 36)
            VStack(alignment: .leading, spacing: 6) {
                header
                bar
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if isRunning {
                    Label("Running. Quit it to clear or reset.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            actions
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button("Reveal App in Finder") { FileActions.reveal(footprint.app.path) }
            Button("Copy Bundle ID") { FileActions.copy(footprint.app.bundleID) }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(footprint.app.name).font(.body.weight(.medium)).lineLimit(1)
            if footprint.app.isAppStore { Pill(text: "App Store", color: .blue) }
            Spacer(minLength: 8)
            Text(Format.bytes(footprint.total)).font(.body.monospacedDigit().weight(.semibold))
        }
    }

    private var bar: some View {
        GeometryReader { proxy in
            let fraction = scale > 0 ? Double(footprint.total) / Double(scale) : 0
            StackedBar(segments: footprint.segments, height: 8, showsLegend: false)
                .frame(width: max(proxy.size.width * fraction, 4))
        }
        .frame(height: 8)
    }

    private var summary: String {
        let app = "App \(Format.bytes(footprint.size(of: .bundle)))"
        let data = "Data \(Format.bytes(footprint.dataSize))"
        let cache = "Cache \(Format.bytes(footprint.cacheSize))"
        return [app, data, cache].joined(separator: " · ")
    }

    private var actions: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if isWorking {
                ProgressView().controlSize(.small).accessibilityLabel("Working on \(footprint.app.name)")
            } else {
                Button("Clear Cache", systemImage: "archivebox", action: onClearCache)
                    .disabled(isRunning || footprint.cacheSize == 0)
                    .help("Moves only cache folders to the Trash. Settings and sign-ins stay.")
                    .accessibilityLabel("Clear cache of \(footprint.app.name)")
                Button("Reset…", systemImage: "arrow.counterclockwise", role: .destructive, action: onReset)
                    .disabled(isRunning || footprint.dataSize == 0)
                    .help("Moves everything except the app itself to the Trash, as if freshly installed.")
                    .accessibilityLabel("Reset \(footprint.app.name)")
            }
        }
        .controlSize(.small)
        .frame(width: 120, alignment: .trailing)
    }
}
