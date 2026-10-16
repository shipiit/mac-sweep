import MacSweepCore
import SwiftUI

/// Wi-Fi, Bluetooth, sharing services, firewall and AirDrop, each with a plain verdict and a fix link.
struct SharingAuditView: View {
    @State private var model = SharingAuditModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatStrip {
                    StatTile(title: "To review", value: Format.count(model.issueCount),
                             detail: model.issueCount == 0 ? "all clear" : "settings worth a look",
                             dot: model.issueCount == 0 ? nil : .orange)
                    StatTile(title: "Medium or high", value: Format.count(model.highCount), detail: "real exposure")
                    StatTile(title: "Passed", value: Format.count(model.passedCount),
                             detail: model.checkedAt.map { "checked \(Format.relative($0))" })
                }
                if model.findings.isEmpty {
                    Card { ProgressView("Checking sharing and network settings…").frame(maxWidth: .infinity) }
                } else {
                    ForEach(model.sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(section.category.rawValue, systemImage: section.category.symbol).font(.headline)
                            EqualHeightGrid(items: section.findings, columns: 2) { SharingFindingCard(finding: $0) }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Sharing & Wi-Fi")
        .toolbar {
            ToolbarItem {
                Button { Task { await model.load() } } label: { Label("Check Again", systemImage: "arrow.clockwise") }
                    .disabled(model.isLoading)
            }
        }
        .task { if model.checkedAt == nil { await model.load() } }
    }
}

private struct SharingFindingCard: View {
    let finding: SharingFinding

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                SymbolBadge(symbol: finding.symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.title).font(.headline)
                    Text(finding.status).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                SeverityPill(severity: finding.severity)
            }
            Text(finding.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Open Settings") { FileActions.open(url: URL(string: finding.settingsURL)) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        .accessibilityElement(children: .contain)
    }
}
