import MacSweepCore
import SwiftUI

struct ScanPlaceholder: View {
    @Environment(\.appAccent) private var accent
    let disk: DiskModel
    let hasFullDiskAccess: Bool
    let onRecheck: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            if !hasFullDiskAccess { FullDiskAccessBanner(onRecheck: onRecheck).frame(maxWidth: 720) }
            Spacer()
            ZStack {
                Circle().fill(accent.opacity(0.1)).frame(width: 132, height: 132)
                Image(systemName: disk.isScanning ? "magnifyingglass" : "internaldrive")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(accent)
                    .symbolEffect(.pulse, isActive: disk.isScanning)
            }
            .accessibilityHidden(true)

            if disk.isScanning, let progress = disk.progress {
                VStack(spacing: 8) {
                    Text("Scanning \(Format.path(disk.rootPath))…").font(.title2.weight(.semibold))
                    Text("\(Format.count(progress.files)) files · \(Format.bytes(progress.bytes))")
                        .font(.system(.title3, design: .monospaced))
                        .contentTransition(.numericText())
                    Text(Format.path(progress.currentPath))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 520)
                    ProgressView().progressViewStyle(.linear).frame(width: 320)
                    Button("Stop") { disk.cancel() }.padding(.top, 6)
                }
            } else {
                VStack(spacing: 8) {
                    Text("See what's filling your Mac").font(.largeTitle.weight(.semibold))
                    Text("MacSweep maps every folder, hidden ones included, then lists caches and build output you can safely clear.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
                HStack(spacing: 12) {
                    Button { disk.scan(root: disk.home) } label: {
                        Label("Scan Home Folder", systemImage: "house").padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    Button { disk.scan(root: "/") } label: {
                        Label("Scan Entire Disk", systemImage: "internaldrive").padding(.horizontal, 8)
                    }
                    .controlSize(.large)
                }
            }
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScanProgressBar: View {
    let disk: DiskModel

    var body: some View {
        HStack(spacing: 10) {
            Text("Rescanning \(Format.path(disk.rootPath))")
            if let progress = disk.progress, progress.files > 0 {
                Text("\(Format.count(progress.files)) files · \(Format.bytes(progress.bytes))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                Text("Starting…").foregroundStyle(.secondary)
            }
            if let fraction = disk.estimatedFraction {
                ProgressView(value: fraction).frame(maxWidth: 260)
            } else {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button("Stop") { disk.cancel() }
        }
        .font(.callout)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
