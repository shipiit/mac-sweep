import MacSweepCore
import SwiftUI

struct ExplorerCard: View {
    @Bindable var disk: DiskModel
    let cleanup: CleanupModel
    let onTrash: (FileNode) -> Void

    @State private var coloring: TreemapColoring = .category
    @State private var hovered: TreemapTile?
    /// Shared with the side panel, which lists the selected folder's contents.
    @Binding var selected: TreemapTile?

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(16)
                Divider()
                breadcrumbBar.padding(.horizontal, 16).padding(.vertical, 10)
                if let focus = disk.focusNode {
                    TreemapView(
                        focus: focus,
                        home: disk.home,
                        coloring: coloring,
                        safety: cleanup.safety(forPath:),
                        safetyVersion: cleanup.cleanableIndex.count,
                        hovered: $hovered,
                        selected: $selected,
                        onOpen: open,
                        onTrash: onTrash
                    )
                    .padding(.horizontal, 13)
                    .frame(minHeight: 400, maxHeight: .infinity)
                }
                Divider().padding(.top, 10)
                footer.padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            SectionHeader(title: "Explorer", subtitle: "Sized by space used. Click a folder to open it. Right-click for more.")
            Spacer()
            Picker("Colour by", selection: $coloring) {
                ForEach(TreemapColoring.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            Button { disk.goUp() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .disabled(disk.breadcrumbs.count <= 1)
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help("Enclosing folder (⌘↑)")
            ForEach(Array(disk.breadcrumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 { Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary).accessibilityHidden(true) }
                Button(crumb.name) { disk.open(crumb.path) }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == disk.breadcrumbs.count - 1 ? .primary : .secondary)
                    .fontWeight(index == disk.breadcrumbs.count - 1 ? .semibold : .regular)
            }
            Spacer()
            if let focus = disk.focusNode {
                Text("\(Format.count(focus.itemCount)) files · \(Format.bytes(focus.size))")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder private var footer: some View {
        if let tile = hovered ?? selected, !tile.isOverflow {
            TileDetailBar(tile: tile, home: disk.home, safety: cleanup.safety(forPath: tile.node.path), onTrash: onTrash)
        } else {
            legend
        }
    }

    @ViewBuilder private var legend: some View {
        HStack(spacing: 16) {
            switch coloring {
            case .category:
                ForEach(StorageCategory.allCases.filter { $0 != .other }) { legendItem($0.rawValue, $0.color) }
            case .cleanup:
                ForEach(CleanupSafety.allCases, id: \.self) { legendItem($0.title, $0.color) }
                legendItem("Keep", Color(nsColor: .systemGray))
            }
            Spacer()
        }
        .font(.caption)
    }

    private func legendItem(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(title).foregroundStyle(.secondary)
        }
    }

    private func open(_ tile: TreemapTile) {
        if tile.isOverflow { return }
        if tile.node.isDirectory, !tile.node.children.isEmpty {
            selected = nil
            withAnimation(.snappy) { disk.open(tile.node.path) }
        } else if tile.depth == 1 {
            withAnimation(.snappy) { disk.open(tile.node.parentPath) }
        }
    }
}
