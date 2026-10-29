import MacSweepCore
import SwiftUI

/// "App footprint & reset" tab content for the Uninstaller: apps sorted by total footprint,
/// with Clear Cache and Reset actions. No toolbar or navigation title of its own.
struct AppFootprintView: View {
    @Environment(\.appAccent) private var accent
    @State private var model = AppFootprintModel.shared
    @State private var search = ""

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            StatStrip {
                StatTile(title: "Apps measured", value: Format.count(model.footprints.count), detail: "Apple apps excluded", dot: accent)
                StatTile(title: "Total footprint", value: Format.bytes(model.totalFootprint), detail: "apps + their data")
                StatTile(title: "App data", value: Format.bytes(model.totalData), detail: "removed by Reset",
                         dot: FootprintCategory.applicationSupport.color)
                StatTile(title: "Caches", value: Format.bytes(model.totalCache), detail: "removed by Clear Cache",
                         dot: FootprintCategory.caches.color)
            }
            controls
            content
        }
        .padding(16)
        .task { if !model.hasLoaded { await model.refresh() } }
        .sheet(item: $model.pendingReset) { plan in
            AppResetSheet(plan: plan,
                          onConfirm: { Task { await model.confirmReset() } },
                          onCancel: { model.pendingReset = nil })
        }
        .alert(model.message ?? "", isPresented: messageShown) { Button("OK", role: .cancel) {} }
    }

    private var messageShown: Binding<Bool> {
        Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })
    }

    private var controls: some View {
        HStack(spacing: 10) {
            TextField("Filter apps", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
            legend
            Spacer()
            if model.isLoading { ProgressView().controlSize(.small).accessibilityLabel("Measuring apps") }
            Button("Measure Again", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                .disabled(model.isLoading)
        }
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { ForEach(FootprintCategory.allCases, id: \.self, content: legendItem) }
            HStack(spacing: 10) { ForEach([FootprintCategory.bundle, .caches, .applicationSupport, .containers], id: \.self, content: legendItem) }
            EmptyView()
        }
        .font(.caption)
    }

    private func legendItem(_ category: FootprintCategory) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(category.color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(category.title).foregroundStyle(.secondary)
        }
    }

    private var visible: [AppFootprint] {
        guard !search.isEmpty else { return model.footprints }
        return model.footprints.filter {
            $0.app.name.localizedCaseInsensitiveContains(search) || $0.app.bundleID.localizedCaseInsensitiveContains(search)
        }
    }

    @ViewBuilder private var content: some View {
        let rows = visible
        if rows.isEmpty {
            Card {
                Group {
                    if model.isLoading || !model.hasLoaded {
                        ContentUnavailableView("Measuring app footprints…", systemImage: "chart.bar.xaxis")
                    } else if !search.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        ContentUnavailableView("No apps to show", systemImage: "app.dashed",
                                               description: Text("Only apps you installed are listed; Apple apps are never reset."))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            }
        } else {
            let scale = model.footprints.first?.total ?? 0
            List(rows) { footprint in
                AppFootprintRow(
                    footprint: footprint,
                    scale: scale,
                    isRunning: model.isRunning(footprint),
                    isWorking: model.working.contains(footprint.id),
                    onClearCache: { Task { await model.clearCache(footprint) } },
                    onReset: { model.prepareReset(footprint) }
                )
            }
            .scrollContentBackground(.hidden)
        }
    }
}

extension AppFootprintModel {
    /// One instance for the app's lifetime, so results stay when you switch pages; Rescan refreshes them.
    static let shared = AppFootprintModel()
}
