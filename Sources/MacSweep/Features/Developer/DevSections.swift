import MacSweepCore
import SwiftUI

/// Rounded list container used by every developer section.
struct DevList<Content: View>: View {
    let title: String
    var trailing: AnyView?
    @ViewBuilder var content: Content

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    trailing
                }
                content
            }
        }
    }
}

struct DockerSection: View {
    let model: DeveloperModel

    var body: some View {
        switch model.docker {
        case .ready(let usage):
            StatStrip {
                ForEach(usage.rows) { row in
                    StatTile(title: row.kind.rawValue, value: Format.bytes(row.size), detail: "\(Format.bytes(row.reclaimable)) reclaimable · \(row.total) total")
                }
            }
            HStack {
                ForEach(DockerPrune.allCases) { kind in
                    let estimate = kind == .buildCache ? usage.row(.buildCache)?.reclaimable ?? 0 : usage.danglingImages.reduce(0) { $0 + $1.size }
                    Button("Remove \(kind.rawValue.lowercased()) (\(Format.bytes(estimate)))") { model.ask(.dockerPrune(kind, estimate: estimate)) }
                        .disabled(model.busy != nil || estimate == 0)
                }
            }
            DevList(title: "Images") {
                ForEach(usage.images.prefix(50)) { image in
                    DevRow(symbol: "shippingbox", title: image.displayName, detail: "\(image.containers) containers · \(image.created)", size: image.size)
                }
            }
            DevList(title: "Volumes") {
                ForEach(usage.volumes.prefix(50)) { volume in
                    DevRow(symbol: "externaldrive", title: volume.name, detail: volume.isUnused ? "Not used by any container" : "In use", size: volume.size)
                }
            }
        case .notInstalled?: Label("Docker isn't installed.", systemImage: "shippingbox").foregroundStyle(.secondary)
        case .notRunning?: Label("Docker is installed but not running. Start Docker Desktop to see its storage.", systemImage: "pause.circle").foregroundStyle(.secondary)
        case .failed(let message)?: Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        case nil: EmptyView()
        }
    }
}

struct RuntimesSection: View {
    let model: DeveloperModel

    var body: some View {
        ForEach(RuntimeLanguage.allCases) { language in
            let versions = model.runtimes.filter { $0.language == language }
            if !versions.isEmpty {
                DevList(title: "\(language.rawValue) · \(versions.count) installed") {
                    ForEach(versions) { version in
                        DevRow(symbol: "chevron.left.forwardslash.chevron.right", title: "\(version.version)", detail: "\(version.manager) · \(Format.path(version.path))",
                               size: version.size, path: version.path) {
                            model.ask(.trash(paths: [version.path], title: "\(language.rawValue) \(version.version)", size: version.size ?? 0))
                        }
                    }
                }
            }
        }
        if !model.globalPackages.isEmpty {
            DevList(title: "Global packages · \(model.globalPackages.count)") {
                ForEach(model.globalPackages) { package in
                    DevRow(symbol: "cube", title: package.name, detail: "\(package.version) · \(package.manager)", size: nil, path: package.path)
                }
            }
        }
        if model.runtimes.isEmpty && model.state(.runtimes) == .loaded {
            Label("No version managers (nvm, fnm, volta, pyenv, rbenv, asdf, uv) found.", systemImage: "info.circle").foregroundStyle(.secondary)
        }
    }
}
