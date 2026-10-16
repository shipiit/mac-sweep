import MacSweepCore
import SwiftUI

/// Every project's node_modules, biggest first, with size bars, activity and bulk clean-up of stale ones.
struct NodeModulesSection: View {
    let model: DeveloperModel
    @State private var selected: Set<String> = []
    @State private var filter: Filter = .all
    @State private var search = ""
    @Environment(\.appAccent) private var accent

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", stale = "Stale", idle = "Idle", active = "Active"
        var id: String { rawValue }
    }

    var body: some View {
        let now = Date()
        let projects = model.nodeProjects.filter { project in
            let activity = ProjectActivity.classify(lastModified: project.lastModified, now: now)
            let matchesFilter = filter == .all || activity.rawValue == filter.rawValue
            return matchesFilter && (search.isEmpty || project.root.localizedCaseInsensitiveContains(search))
        }
        let stale = model.nodeProjects.filter { ProjectActivity.classify(lastModified: $0.lastModified, now: now) == .stale }
        let largest = max(model.nodeProjects.map(\.totalSize).max() ?? 1, 1)
        let chosen = model.nodeProjects.filter { selected.contains($0.id) }
        if !model.nodeProjects.isEmpty {
            StatStrip {
                StatTile(title: "node_modules total", value: Format.bytes(model.nodeProjects.reduce(0) { $0 + $1.totalSize }), detail: "\(model.nodeProjects.count) projects")
                StatTile(title: "Stale (90+ days)", value: Format.bytes(stale.reduce(0) { $0 + $1.totalSize }), detail: "\(stale.count) projects", dot: stale.isEmpty ? .green : .orange)
                StatTile(title: "Selected", value: Format.bytes(chosen.reduce(0) { $0 + $1.totalSize }), detail: "\(chosen.count) projects")
            }
            HStack(spacing: 10) {
                Picker("Show", selection: $filter) { ForEach(Filter.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 280)
                TextField("Search projects", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                Spacer()
                Button("Select Stale") { selected = Set(stale.map(\.id)) }.disabled(stale.isEmpty)
                Button {
                    model.ask(.trash(paths: chosen.flatMap { $0.folders.map(\.path) }, title: "node_modules of \(chosen.count) projects",
                                     size: chosen.reduce(0) { $0 + $1.totalSize }))
                } label: { Label("Clear Selected", systemImage: "trash") }
                .buttonStyle(.borderedProminent).disabled(chosen.isEmpty || model.busy != nil)
            }
            VStack(spacing: 0) {
                ForEach(projects) { project in
                    row(project, activity: ProjectActivity.classify(lastModified: project.lastModified, now: now), largest: largest)
                    if project.id != projects.last?.id { Divider().padding(.leading, 44) }
                }
                if projects.isEmpty { Text("No projects match.").foregroundStyle(.secondary).padding(16) }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
            Text("Clearing moves node_modules to the Trash. Run npm, pnpm or yarn install in the project to bring it back.")
                .font(.caption).foregroundStyle(.secondary)
        } else if model.state(.nodeModules) == .loaded {
            Label("No node_modules folders found in your home folder.", systemImage: "checkmark.seal").foregroundStyle(.secondary)
        }
    }

    private func row(_ project: NodeProject, activity: ProjectActivity, largest: UInt64) -> some View {
        let color: Color = activity == .stale ? .orange : activity == .idle ? .yellow : .green
        return HStack(spacing: 12) {
            Toggle(project.name, isOn: Binding(get: { selected.contains(project.id) }, set: { isOn in
                if isOn { selected.insert(project.id) } else { selected.remove(project.id) }
            }))
            .toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(project.name).fontWeight(.semibold)
                    Label(activity.rawValue, systemImage: activity == .stale ? "moon.zzz.fill" : activity == .idle ? "pause.circle.fill" : "bolt.fill")
                        .font(.caption2.weight(.semibold)).foregroundStyle(color)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(color.opacity(0.12), in: Capsule())
                    if project.folders.count > 1 { Text("\(project.folders.count) folders").font(.caption).foregroundStyle(.secondary) }
                }
                Text(Format.path(project.root) + (project.lastModified.map { " · changed \(Format.relative($0))" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                GeometryReader { proxy in
                    Capsule().fill(accent.opacity(0.7))
                        .frame(width: max(proxy.size.width * Double(project.totalSize) / Double(largest), 3))
                }
                .frame(height: 4)
            }
            Spacer(minLength: 12)
            Text(project.isMeasured ? Format.bytes(project.totalSize) : "Measuring…").monospacedDigit().fontWeight(.medium).frame(width: 90, alignment: .trailing)
            Button { FileActions.reveal(project.root) } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless).help("Reveal").accessibilityLabel("Reveal \(project.name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
