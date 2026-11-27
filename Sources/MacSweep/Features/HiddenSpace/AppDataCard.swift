import MacSweepCore
import SwiftUI

/// The removable parts of the biggest app-data folders: caches and sandboxes apps rebuild on their own.
struct AppDataCard: View {
    @Bindable var model: HiddenSpaceModel
    @State private var confirming = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    SectionHeader(title: "Reclaimable app data",
                                  subtitle: "Your biggest app folders, split into what the app rebuilds by itself and what is yours. Settings, history and logins are never listed here.")
                    Spacer()
                    Button("Select Caches") { model.selectCaches() }.disabled(model.appData.isEmpty)
                    Button(model.selectedParts.isEmpty ? "Move to Trash…" : "Move \(Format.bytes(model.selectedPartsSize)) to Trash…") { confirming = true }
                        .disabled(model.selectedParts.isEmpty || model.busy != nil)
                }
                if model.appData.isEmpty {
                    if model.isMeasuringFolders {
                        HStack { ProgressView().controlSize(.small); Text("Looking inside your biggest app folders…").foregroundStyle(.secondary) }
                    } else {
                        Label("No app folder has a cache worth clearing.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    }
                }
                ForEach(model.appData) { group in
                    AppDataGroupView(group: group, model: model)
                }
            }
        }
        .confirmationDialog("Move \(model.selectedParts.count) items (\(Format.bytes(model.selectedPartsSize))) to the Trash?", isPresented: $confirming) {
            Button("Move to Trash") { Task { await model.trashSelectedParts() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They stay in the Trash until you empty it, so you can put one back if an app misbehaves. Items of apps that are open are skipped.")
        }
    }
}

private struct AppDataGroupView: View {
    let group: HiddenSpaceModel.AppDataGroup
    @Bindable var model: HiddenSpaceModel

    var body: some View {
        let isRunning = model.isAppRunning(group.app)
        // When every item has the same explanation (a tool cache folder), say it once instead of on each row.
        let sharedNote = Set(group.removable.map(\.note)).count == 1 && group.removable.count > 1 ? group.removable.first?.note : nil
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(Format.path(group.folder)).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                if isRunning, let app = group.app { Pill(text: "Quit \(app) first", color: .orange) }
                Spacer()
                Text("\(Format.bytes(group.removable.reduce(0) { $0 + $1.size })) removable").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button("Reveal", systemImage: "folder") { FileActions.reveal(group.folder) }.labelStyle(.iconOnly).buttonStyle(.borderless)
            }
            if let sharedNote { Text(sharedNote).font(.caption).foregroundStyle(.secondary) }
            ForEach(group.removable) { part in
                HStack(alignment: .center, spacing: 10) {
                    Toggle("Select \(part.name)", isOn: binding(part)).labelsHidden().toggleStyle(.checkbox).disabled(isRunning)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(part.name).font(.callout.monospaced())
                        if sharedNote == nil { Text(part.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    }
                    Spacer()
                    Pill(text: part.kind.rawValue, color: part.kind == .cache ? .green : .orange)
                    Text(Format.bytes(part.size)).font(.callout.monospacedDigit()).frame(width: 80, alignment: .trailing)
                }
                .padding(.leading, 4)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func binding(_ part: FolderPart) -> Binding<Bool> {
        Binding(get: { model.selectedParts.contains(part.id) },
                set: { if $0 { model.selectedParts.insert(part.id) } else { model.selectedParts.remove(part.id) } })
    }
}
