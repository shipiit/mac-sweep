import MacSweepCore
import SwiftUI

/// Icon, title, detail, size and optional reveal / trash buttons.
struct DevRow: View {
    let symbol: String
    let title: String
    let detail: String
    let size: UInt64?
    var path: String?
    var onTrash: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let size { Text(Format.bytes(size)).monospacedDigit().foregroundStyle(.secondary) }
            if let path {
                Button { FileActions.reveal(path) } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless).help("Reveal in Finder").accessibilityLabel("Reveal \(title)")
            }
            if let onTrash {
                Button(action: onTrash) { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Move to Trash").accessibilityLabel("Move \(title) to Trash")
            }
        }
        .padding(.vertical, 3)
    }
}

struct XcodeSection: View {
    let model: DeveloperModel

    var body: some View {
        EqualHeightGrid(items: model.xcodeLocations, columns: 2) { location in
            VStack(alignment: .leading, spacing: 6) {
                Text(location.title).font(.headline)
                Text(location.size.map(Format.bytes) ?? "Measuring…").font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(location.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack {
                    Button("Reveal") { FileActions.reveal(location.path) }
                    Button("Move Contents to Trash") {
                        model.ask(.trash(paths: XcodeStorage.children(of: location.path), title: location.title, size: location.size ?? 0))
                    }
                    .disabled(location.itemCount == 0 || model.busy != nil)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        }
        let unavailable = model.simulators.filter { !$0.isAvailable }
        DevList(title: "Simulators · \(model.simulators.count)",
                trailing: AnyView(Button("Delete \(unavailable.count) unavailable") { model.ask(.deleteUnavailableSimulators(count: unavailable.count)) }
                    .disabled(unavailable.isEmpty || model.busy != nil))) {
            if let error = model.simulatorError { Text(error).foregroundStyle(.secondary) }
            ForEach(model.simulators.sorted { $0.dataSize > $1.dataSize }.prefix(60)) { simulator in
                DevRow(symbol: simulator.isBooted ? "iphone.radiowaves.left.and.right" : "iphone", title: simulator.name,
                       detail: "\(simulator.runtime)\(simulator.isAvailable ? "" : " · unavailable")" + (simulator.lastBooted.map { " · used \(Format.relative($0))" } ?? ""),
                       size: simulator.dataSize)
            }
        }
    }
}

struct NodeModulesSection: View {
    let model: DeveloperModel

    var body: some View {
        if model.nodeProjects.isEmpty && !model.state(.nodeModules).isLoading {
            ModuleIntro(title: "node_modules", subtitle: "Every project's dependencies, biggest and stalest first.",
                        symbol: "folder.badge.gearshape", tint: .green,
                        bullets: [("clock", "Last opened", "Projects you haven't touched in months are safe to clear; npm install brings them back."),
                                  ("trash", "Goes to the Trash", "Nothing is deleted outright.")],
                        actionTitle: "Find node_modules") { Task { await model.refresh(.nodeModules) } }
                .frame(minHeight: 420)
        } else {
            let stale = model.nodeProjects.filter { ProjectActivity.classify(lastModified: $0.lastModified, now: Date()) == .stale }
            StatStrip {
                StatTile(title: "Total", value: Format.bytes(model.nodeProjects.reduce(0) { $0 + $1.totalSize }), detail: "\(model.nodeProjects.count) projects")
                StatTile(title: "Stale projects", value: "\(stale.count)", detail: Format.bytes(stale.reduce(0) { $0 + $1.totalSize }) + " in their node_modules")
            }
            DevList(title: "Projects") {
                ForEach(model.nodeProjects) { project in
                    let activity = ProjectActivity.classify(lastModified: project.lastModified, now: Date())
                    DevRow(symbol: activity == .stale ? "moon.zzz" : "folder", title: project.name,
                           detail: "\(activity.rawValue)" + (project.lastModified.map { " · changed \(Format.relative($0))" } ?? "") + " · \(Format.path(project.root))",
                           size: project.isMeasured ? project.totalSize : nil, path: project.root) {
                        model.ask(.trash(paths: project.folders.map(\.path), title: "\(project.name)'s node_modules", size: project.totalSize))
                    }
                }
            }
        }
    }
}

struct ServicesSection: View {
    let model: DeveloperModel
    @State private var logService: DevService?

    var body: some View {
        if let error = model.servicesError { Label(error, systemImage: "info.circle").foregroundStyle(.secondary) }
        DevList(title: "Services") {
            if model.services.isEmpty { Text("No Homebrew or launchd dev services found.").foregroundStyle(.secondary) }
            ForEach(model.services) { service in
                HStack(spacing: 10) {
                    Image(systemName: service.state == .running ? "play.circle.fill" : service.state == .error ? "exclamationmark.circle.fill" : "stop.circle")
                        .foregroundStyle(service.state == .running ? .green : service.state == .error ? .red : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(service.name).fontWeight(.medium)
                        Text("\(service.state.rawValue) · \(service.source.rawValue)" + (service.pid.map { " · PID \($0)" } ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ForEach(DevServiceAction.allCases, id: \.self) { action in
                        Button(action.rawValue) { Task { await model.perform(action, on: service) } }
                            .disabled(model.busy != nil || (action == .start && service.state == .running) || (action == .stop && service.state != .running))
                    }
                    Button("Logs") { logService = service }.disabled(DevServiceControl.logPaths(for: service).isEmpty)
                }
                .controlSize(.small)
            }
        }
        .sheet(item: $logService) { service in LogSheet(service: service) }
    }
}

private struct LogSheet: View {
    let service: DevService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let path = DevServiceControl.logPaths(for: service).first
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(service.name) log").font(.headline)
                Spacer()
                if let path { Button("Reveal") { FileActions.reveal(path) } }
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                Text((path.flatMap { LogTail.read(path: $0) } ?? ["No log found."]).joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 720, height: 460)
    }
}
