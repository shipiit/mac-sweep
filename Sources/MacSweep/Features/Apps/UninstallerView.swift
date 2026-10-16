import MacSweepCore
import SwiftUI

/// CleanMyMac-style uninstaller: categories on the left, checkable apps on the right,
/// one round Uninstall button that removes apps together with their leftovers.
struct UninstallerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appAccent) private var accent
    @State private var category: CategoryChoice = .apps(.all)
    @State private var search = ""
    @State private var checked = Set<String>()
    @State private var detail: InstalledApp?
    @State private var confirm = false
    @State private var orphanChecked = Set<String>()

    enum CategoryChoice: Hashable {
        case apps(AppCategory)
        case leftovers
    }

    var body: some View {
        @Bindable var model = app.apps
        HStack(spacing: 0) {
            categories(model)
                .frame(width: 230)
            Divider()
            VStack(spacing: 0) {
                switch category {
                case .apps(let filter): appList(filter, model: model)
                case .leftovers: orphanList(model)
                }
                actionBar(model)
            }
        }
        .navigationTitle("Uninstaller")
        .navigationSubtitle("\(model.apps.count) apps · \(Format.bytes(model.apps.reduce(0) { $0 + ($1.size ?? 0) }))")
        .searchable(text: $search, prompt: "Search apps")
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }.disabled(model.isLoading) }
        .popover(item: $detail) { AppUninstallInspector(installed: $0, model: model).frame(width: 380, height: 460) }
        .confirmationDialog(confirmTitle(model), isPresented: $confirm, titleVisibility: .visible) {
            Button("Uninstall", role: .destructive) { Task { await uninstallChecked(model) } }
        } message: {
            Text("Each app and its leftovers move to the Trash. Running apps are skipped; quit them first.")
        }
        .alert(model.message ?? "", isPresented: isPresented($model.message)) { Button("OK", role: .cancel) {} }
        .task { if model.apps.isEmpty { await model.refresh() } }
    }

    private func categories(_ model: AppsModel) -> some View {
        List(selection: $category) {
            Section {
                row("All Applications", .apps(.all), count: model.apps.count)
                row("Unused", .apps(.unused), count: model.apps.filter { AppCategories.matches($0, .unused) }.count)
                row("Large (500 MB+)", .apps(.large), count: model.apps.filter { AppCategories.matches($0, .large) }.count)
                row("Leftovers", .leftovers, count: model.orphans.count)
            }
            Section("Stores") {
                row("App Store", .apps(.appStore), count: model.apps.filter(\.isAppStore).count)
                row("Other", .apps(.other), count: model.apps.filter { !$0.isAppStore }.count)
            }
            Section("Vendors") {
                ForEach(AppCategories.vendors(model.apps), id: \.name) { vendor in
                    row(vendor.name, .apps(.vendor(vendor.name)), count: vendor.count)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func row(_ title: String, _ value: CategoryChoice, count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
        }
        .tag(value)
    }

    private func appList(_ filter: AppCategory, model: AppsModel) -> some View {
        let apps = model.apps
            .filter { AppCategories.matches($0, filter) }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { ($0.size ?? 0) > ($1.size ?? 0) }
        return List(apps) { item in
            HStack(spacing: 12) {
                Toggle(isOn: Binding(get: { checked.contains(item.id) },
                                     set: { if $0 { checked.insert(item.id) } else { checked.remove(item.id) } })) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Select \(item.name)")
                FileIcon(path: item.path, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name).font(.body.weight(.medium))
                        if item.isAppStore { Pill(text: "App Store", color: .blue) }
                    }
                    Text("v\(item.version) · last used \(item.lastUsed.map { Format.relative($0) } ?? "never / unknown")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.size.map(Format.bytes) ?? "…").monospacedDigit()
                Button { detail = item } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
                    .help("Show leftovers and details")
                    .accessibilityLabel("Details for \(item.name)")
            }
            .padding(.vertical, 4)
        }
        .scrollContentBackground(.hidden)
        .overlay { if apps.isEmpty { ContentUnavailableView(model.isLoading ? "Finding apps…" : "No apps here", systemImage: "app.dashed") } }
    }

    private func orphanList(_ model: AppsModel) -> some View {
        List(model.orphans.filter { search.isEmpty || $0.path.localizedCaseInsensitiveContains(search) }) { orphan in
            HStack(spacing: 12) {
                Toggle(isOn: Binding(get: { orphanChecked.contains(orphan.path) },
                                     set: { if $0 { orphanChecked.insert(orphan.path) } else { orphanChecked.remove(orphan.path) } })) { EmptyView() }
                    .toggleStyle(.checkbox)
                FileIcon(path: orphan.path, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text((orphan.path as NSString).lastPathComponent)
                    Text(Format.path((orphan.path as NSString).deletingLastPathComponent) + " · untouched since \(Format.relative(orphan.modified))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(Format.bytes(orphan.size)).monospacedDigit()
            }
        }
        .scrollContentBackground(.hidden)
        .overlay { if model.orphans.isEmpty { ContentUnavailableView("No leftovers found", systemImage: "checkmark.circle") } }
    }

    private func actionBar(_ model: AppsModel) -> some View {
        let isLeftovers = category == .leftovers
        let count = isLeftovers ? orphanChecked.count : checked.count
        let size = isLeftovers
            ? model.orphans.filter { orphanChecked.contains($0.path) }.reduce(0) { $0 + $1.size }
            : model.apps.filter { checked.contains($0.id) }.reduce(0) { $0 + ($1.size ?? 0) }
        return HStack {
            Text(count == 0 ? "Select apps to remove" : "\(count) selected · \(Format.bytes(size))").foregroundStyle(.secondary)
            Spacer()
            Button {
                if isLeftovers {
                    Task { await model.removeOrphans(orphanChecked); orphanChecked.removeAll() }
                } else {
                    confirm = true
                }
            } label: {
                Text(isLeftovers ? "Remove" : "Uninstall").font(.headline).foregroundStyle(.white)
                    .frame(width: 92, height: 92)
                    .background(Circle().fill(count == 0 ? Color.gray.opacity(0.4) : accent))
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 4))
            }
            .buttonStyle(.plain)
            .disabled(count == 0)
            .accessibilityLabel(isLeftovers ? "Remove selected leftovers" : "Uninstall selected apps")
            Spacer()
            Text("Goes to the Trash").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func confirmTitle(_ model: AppsModel) -> String {
        let names = model.apps.filter { checked.contains($0.id) }.map(\.name)
        return names.count == 1 ? "Uninstall \(names[0])?" : "Uninstall \(names.count) apps?"
    }

    private func uninstallChecked(_ model: AppsModel) async {
        for item in model.apps.filter({ checked.contains($0.id) }) {
            await model.loadLeftovers(for: item)
            await model.uninstall(item, includeLeftovers: Set((model.leftovers[item.id] ?? []).map(\.path)))
        }
        checked.removeAll()
    }
}

