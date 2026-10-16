import MacSweepCore
import SwiftUI

struct UpdaterView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var model = app.updates
        if model.lastChecked == nil {
            ModuleIntro(title: "Updater", subtitle: "Keep macOS and the apps you installed with Homebrew up to date from one place.",
                        symbol: "arrow.down.app.fill", tint: .green,
                        bullets: [("clock.arrow.circlepath", "Latest versions only", "Checks macOS, Homebrew apps and tools for newer releases."),
                                  ("square.on.square", "Avoid incompatibilities", "Outdated apps are the most common cause of crashes and security holes.")],
                        actionTitle: "Check for Updates", isWorking: model.isChecking) { Task { await model.check() } }
                .navigationTitle("Updater")
        } else {
            updateList(model)
        }
    }

    private func updateList(_ model: UpdaterModel) -> some View {
        @Bindable var model = model
        return List {
            Section("macOS & Apple") {
                let system = model.updates.filter { $0.source == .macOS }
                if system.isEmpty { Text(model.isChecking ? "Checking…" : "macOS is up to date.").foregroundStyle(.secondary) }
                ForEach(system) { update in
                    row(update) {
                        Button("Open Software Update") {
                            FileActions.open(url: URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"))
                        }
                    }
                }
            }
            Section("Homebrew") {
                let brew = model.updates.filter { $0.source != .macOS }
                if Updater.brewPath == nil {
                    Text("Homebrew isn't installed.").foregroundStyle(.secondary)
                } else if brew.isEmpty {
                    Text(model.isChecking ? "Checking…" : "Everything installed with Homebrew is current.").foregroundStyle(.secondary)
                }
                ForEach(brew) { update in
                    row(update) {
                        if model.upgrading.contains(update.id) {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Update") { Task { await model.upgrade(update) } }
                        }
                    }
                }
            }
            Section("App Store") {
                Button("Open App Store Updates") { FileActions.open(url: URL(string: "macappstore://showUpdatesPage")) }
            }
        }
        .navigationTitle("Updater")
        .navigationSubtitle(model.lastChecked.map { "Checked \(Format.relative($0))" } ?? "Not checked yet")
        .toolbar {
            Button("Check Now", systemImage: "arrow.clockwise") { Task { await model.check() } }
                .disabled(model.isChecking)
        }
        .alert(model.message ?? "", isPresented: isPresented($model.message)) { Button("OK", role: .cancel) {} }
    }

    private func row<Action: View>(_ update: AvailableUpdate, @ViewBuilder action: () -> Action) -> some View {
        HStack {
            Image(systemName: update.source == .macOS ? "apple.logo" : "shippingbox").foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading) {
                Text(update.name).fontWeight(.medium)
                Text(update.installed.isEmpty ? "Version \(update.available)" : "\(update.installed) → \(update.available)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if update.needsRestart { Pill(text: "Restart", color: .orange) }
            Pill(text: update.source.rawValue)
            Spacer()
            action()
        }
    }
}

struct ExtensionsView: View {
    @Environment(AppModel.self) private var app
    @State private var pending: SystemExtensionItem?
    @State private var riskFilter: ExtensionRisk?

    var body: some View {
        List {
            Section {
                let groups = ExtensionGroup.group(app.security.extensions).filter { riskFilter == nil || $0.risk == riskFilter }
                if groups.isEmpty { Text(app.security.isRunning ? "Scanning…" : "None found").foregroundStyle(.secondary) }
                ForEach(groups) { ExtensionGroupRow(group: $0) }
            } header: {
                HStack {
                    Text("Browser extensions · Chrome, Brave, Edge, Arc, Firefox, Safari")
                    Spacer()
                    Picker("Risk", selection: $riskFilter) {
                        Text("All").tag(ExtensionRisk?.none)
                        ForEach(ExtensionRisk.allCases.reversed(), id: \.self) { Text($0.title).tag(ExtensionRisk?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            ForEach(SystemExtensionItem.Kind.allCases, id: \.self) { kind in
                let items = app.addOns.items.filter { $0.kind == kind }
                if !items.isEmpty {
                    Section(kind.rawValue) {
                        ForEach(items) { item in
                            HStack {
                                FileIcon(path: item.path)
                                Text(item.name)
                                Pill(text: item.isUserInstalled ? "Just you" : "All users")
                                Spacer()
                                Button("Reveal") { FileActions.reveal(item.path) }
                                if item.isUserInstalled { Button("Remove…") { pending = item } }
                            }
                        }
                    }
                }
            }
            Section("Startup") {
                Button("Manage Startup Items") { app.section = .startup }
                Button("Login Items & Extensions in System Settings") { FileActions.open(url: Permissions.loginItemsSettingsURL) }
            }
        }
        .navigationTitle("Extensions")
        .task { await app.addOns.refresh() }
        .confirmationDialog("Move \(pending?.name ?? "") to the Trash?", isPresented: isPresented($pending), titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { if let pending { app.addOns.remove(pending) } }
        }
    }
}
