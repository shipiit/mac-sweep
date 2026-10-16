import MacSweepCore
import SwiftUI

/// Homebrew at a glance: cleanup card, then searchable, foldable lists of outdated apps and tools.
struct BrewSection: View {
    let model: DeveloperModel
    @State private var search = ""
    @State private var showsCasks = true
    @State private var showsFormulae = false
    @Environment(\.appAccent) private var accent

    var body: some View {
        if let brew = model.brew {
            HStack(spacing: 16) {
                Image(systemName: "mug.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 50, height: 50).background(.orange, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(Format.bytes(brew.cleanup.reclaimable)) of old downloads and versions").font(.headline)
                    Text("\(brew.cleanup.itemCount) files · \(brew.outdatedCasks.count) apps and \(brew.outdatedFormulae.count) tools have updates")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.ask(.brewCleanup(estimate: brew.cleanup.reclaimable)) } label: { Label("Clean Up", systemImage: "sparkles") }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy != nil || brew.cleanup.reclaimable == 0)
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
            TextField("Search outdated packages", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
            group("Apps (casks)", items: filtered(brew.outdatedCasks), isExpanded: $showsCasks, symbol: "app.fill")
            group("Command-line tools (formulae)", items: filtered(brew.outdatedFormulae), isExpanded: $showsFormulae, symbol: "terminal.fill")
            Text("Update everything with `brew upgrade` in Terminal, or open Updater to update apps one by one.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func filtered(_ items: [AvailableUpdate]) -> [AvailableUpdate] {
        search.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private func group(_ title: String, items: [AvailableUpdate], isExpanded: Binding<Bool>, symbol: String) -> some View {
        DisclosureGroup(isExpanded: Binding(get: { isExpanded.wrappedValue || !search.isEmpty }, set: { isExpanded.wrappedValue = $0 })) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 8)], spacing: 8) {
                ForEach(items) { update in
                    HStack(spacing: 8) {
                        Image(systemName: symbol).foregroundStyle(accent).font(.caption).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(update.name).lineLimit(1)
                            Text("\(update.installed) → \(update.available)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Text(title).font(.headline)
                Text("\(items.count)").font(.caption.monospacedDigit().weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}
