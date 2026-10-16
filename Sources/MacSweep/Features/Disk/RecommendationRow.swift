import MacSweepCore
import SwiftUI

struct SelectionCheckbox: View {
    @Environment(\.appAccent) private var accent
    let state: CleanupModel.SelectionState
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(state == .none ? Color.secondary : accent)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(state == .all ? "Selected" : state == .partial ? "Partly selected" : "Not selected")
    }

    private var symbol: String {
        switch state {
        case .none: "square"
        case .partial: "minus.square.fill"
        case .all: "checkmark.square.fill"
        }
    }
}

struct RecommendationRow: View {
    let item: CleanupItem
    let cleanup: CleanupModel
    @State private var showsDetail = false

    var body: some View {
        HStack(spacing: 10) {
            SelectionCheckbox(state: cleanup.selectionState(item), label: "Select \(item.rule.title)") {
                withAnimation(.snappy(duration: 0.15)) { cleanup.toggle(item) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.rule.title).fontWeight(.medium)
                Text(summary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(Format.bytes(item.size))
                .font(.system(.body, design: .monospaced).weight(.semibold))
            Button { showsDetail = true } label: {
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show \(item.targets.count) locations for \(item.rule.title)")
            .popover(isPresented: $showsDetail, arrowEdge: .trailing) {
                CleanupDetailView(item: item, cleanup: cleanup)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var summary: String {
        guard let first = item.targets.first else { return "" }
        let more = item.targets.count > 1 ? "  +\(item.targets.count - 1) more" : ""
        return Format.path(first.path) + more
    }
}

struct CleanupDetailView: View {
    let item: CleanupItem
    let cleanup: CleanupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: item.rule.title, subtitle: item.rule.detail)
                Spacer()
                Pill(text: item.rule.safety.title, color: item.rule.safety.color)
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(item.targets) { target in
                        HStack(spacing: 8) {
                            SelectionCheckbox(
                                state: cleanup.selected.contains(target.path) ? .all : .none,
                                label: "Select \(target.path)"
                            ) { cleanup.toggle(target) }
                            FileIcon(path: target.path)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Format.path(target.path)).lineLimit(1).truncationMode(.middle)
                                Text("Modified \(Format.relative(target.modified))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Format.bytes(target.size)).monospacedDigit()
                            Button { FileActions.reveal(target.path) } label: { Image(systemName: "magnifyingglass") }
                                .buttonStyle(.borderless)
                                .help("Reveal in Finder")
                                .accessibilityLabel("Reveal \(target.path) in Finder")
                        }
                    }
                }
            }
            .frame(maxHeight: 340)
        }
        .padding(16)
        .frame(width: 520)
    }
}
