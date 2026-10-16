import MacSweepCore
import SwiftUI

enum TreemapColoring: String, CaseIterable, Identifiable {
    case category = "Category"
    case cleanup = "Cleanup"

    var id: String { rawValue }
}

/// Interactive treemap. The tiles render in one Equatable canvas that redraws only when the layout
/// or colouring changes; hover and selection are drawn on a separate lightweight overlay so moving
/// the mouse never repaints hundreds of tiles.
struct TreemapView: View {
    let focus: FileNode
    let home: String
    let coloring: TreemapColoring
    let safety: (String) -> CleanupSafety?
    /// Changes whenever the set of cleanable paths changes, so hatching is recomputed.
    let safetyVersion: Int
    @Binding var hovered: TreemapTile?
    @Binding var selected: TreemapTile?
    let onOpen: (TreemapTile) -> Void
    let onTrash: (FileNode) -> Void

    @State private var tiles: [TreemapTile] = []
    @State private var tileSafety: [String: CleanupSafety] = [:]
    @State private var size: CGSize = .zero

    var body: some View {
        ZStack {
            TreemapCanvas(tiles: tiles, coloring: coloring, tileSafety: tileSafety)
                .equatable()
            TreemapHighlight(hovered: hovered, selected: selected, coloring: coloring, tileSafety: tileSafety)
        }
        .id(focus.path)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
        .onChange(of: size) { relayout() }
        .onChange(of: focus) { relayout() }
        .onChange(of: safetyVersion) { refreshSafety() }
        .onAppear(perform: relayout)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                let hit = TreemapLayout.hitTest(tiles, at: point)
                if hit?.id != hovered?.id { hovered = hit }
            case .ended:
                hovered = nil
            }
        }
        .onTapGesture(coordinateSpace: .local) { location in
            guard let tile = TreemapLayout.hitTest(tiles, at: location) else { return }
            selected = tile.isOverflow ? nil : tile
            onOpen(tile)
        }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Disk map of \(focus.name)")
        .accessibilityChildren { accessibilityList }
    }

    private func relayout() {
        guard size.width > 0, size.height > 0 else { return }
        tiles = TreemapLayout.tiles(for: focus, in: CGRect(origin: .zero, size: size), home: home)
        refreshSafety()
    }

    private func refreshSafety() {
        var map: [String: CleanupSafety] = [:]
        for tile in tiles where !tile.isOverflow {
            if let value = safety(tile.node.path) { map[tile.id] = value }
        }
        tileSafety = map
    }

    @ViewBuilder private var contextMenu: some View {
        if let tile = hovered, !tile.isOverflow {
            let node = tile.node
            Text(node.name)
            if node.isDirectory { Button("Open") { onOpen(tile) } }
            Button("Reveal in Finder") { FileActions.reveal(node.path) }
            Button("Copy Path") { FileActions.copy(node.path) }
            Divider()
            Button("Move to Trash…", role: .destructive) { onTrash(node) }
                .disabled(!PathGuard.canRemove(node.path, home: home, extraProtected: [Bundle.main.bundlePath]))
        }
    }

    private var accessibilityList: some View {
        ForEach(tiles.filter { $0.depth == 0 && !$0.isOverflow }) { tile in
            Button("\(tile.node.name), \(Format.bytes(tile.node.size))") { onOpen(tile) }
        }
    }
}

enum TreemapPalette {
    static func color(for tile: TreemapTile, coloring: TreemapColoring, safety: CleanupSafety?) -> Color {
        switch coloring {
        case .category: tile.category.color
        case .cleanup: safety?.color ?? Color(nsColor: .systemGray)
        }
    }

    static func shape(_ tile: TreemapTile) -> Path {
        RoundedRectangle(cornerRadius: tile.depth == 0 ? 8 : 5, style: .continuous).path(in: tile.rect)
    }
}

private struct TreemapCanvas: View, Equatable {
    let tiles: [TreemapTile]
    let coloring: TreemapColoring
    let tileSafety: [String: CleanupSafety]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.coloring == rhs.coloring && lhs.tileSafety == rhs.tileSafety
            && lhs.tiles.count == rhs.tiles.count
            && zip(lhs.tiles, rhs.tiles).allSatisfy { $0.id == $1.id && $0.rect == $1.rect && $0.node.size == $1.node.size }
    }

    var body: some View {
        Canvas { context, _ in
            for tile in tiles { draw(tile, in: &context) }
        }
    }

    private func draw(_ tile: TreemapTile, in context: inout GraphicsContext) {
        let safety = tileSafety[tile.id]
        let color = TreemapPalette.color(for: tile, coloring: coloring, safety: safety)
        let shape = TreemapPalette.shape(tile)
        let opacity = tile.isOverflow ? 0.08 : (tile.depth == 0 ? 0.16 : 0.3)
        context.fill(shape, with: .color(color.opacity(opacity)))
        if safety != nil, !tile.hasNested { drawHatch(tile.rect, clip: shape, color: color, context: &context) }
        context.stroke(shape, with: .color(color.opacity(tile.depth == 0 ? 0.75 : 0.6)), lineWidth: 1)
        drawLabels(tile, context: &context)
    }

    private func drawHatch(_ rect: CGRect, clip: Path, color: Color, context: inout GraphicsContext) {
        context.drawLayer { layer in
            layer.clip(to: clip)
            var lines = Path()
            var x = rect.minX - rect.height
            while x < rect.maxX {
                lines.move(to: CGPoint(x: x, y: rect.maxY))
                lines.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                x += 7
            }
            layer.stroke(lines, with: .color(color.opacity(0.45)), lineWidth: 1)
        }
    }

    private func drawLabels(_ tile: TreemapTile, context: inout GraphicsContext) {
        let rect = tile.rect
        guard rect.width > 30, rect.height > 18 else { return }
        let sizeText = Format.bytes(tile.node.size)
        let headerSize = context.resolve(Text(sizeText).font(.system(size: 11, design: .monospaced)))
        let reserved = tile.hasNested ? headerSize.measure(in: rect.size).width + 14 : 0
        let nameFont: Font = tile.depth == 0 ? .system(size: 12, weight: .semibold) : .system(size: 11, weight: .medium)
        let name = fitted(tile.node.name, font: nameFont, width: rect.width - 16 - reserved, context: context)
        context.draw(
            Text(name).font(nameFont).foregroundStyle(tile.isOverflow ? .secondary : .primary),
            at: CGPoint(x: rect.minX + 8, y: rect.minY + 6), anchor: .topLeading
        )
        if tile.hasNested {
            context.draw(Text(sizeText).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary),
                         at: CGPoint(x: rect.maxX - 8, y: rect.minY + 6), anchor: .topTrailing)
        } else if rect.height > 44, rect.width > 64 {
            let big = rect.width > 140 && rect.height > 90
            let label = Text(sizeText)
                .font(.system(size: big ? 20 : 12, weight: big ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(big ? .primary : .secondary)
            context.draw(label, at: CGPoint(x: rect.minX + 8, y: rect.maxY - 6), anchor: .bottomLeading)
        }
    }

    /// Truncates with an ellipsis so labels never spill past their tile.
    private func fitted(_ text: String, font: Font, width: CGFloat, context: GraphicsContext) -> String {
        guard width > 12 else { return "" }
        func fits(_ candidate: String) -> Bool {
            context.resolve(Text(candidate).font(font)).measure(in: CGSize(width: CGFloat.infinity, height: 40)).width <= width
        }
        if fits(text) { return text }
        var low = 0
        var high = text.count
        while low < high {
            let mid = (low + high + 1) / 2
            if fits(String(text.prefix(mid)) + "…") { low = mid } else { high = mid - 1 }
        }
        return low < 2 ? "" : String(text.prefix(low)) + "…"
    }
}

private struct TreemapHighlight: View {
    let hovered: TreemapTile?
    let selected: TreemapTile?
    let coloring: TreemapColoring
    let tileSafety: [String: CleanupSafety]

    var body: some View {
        Canvas { context, _ in
            if let selected, !selected.isOverflow {
                let color = TreemapPalette.color(for: selected, coloring: coloring, safety: tileSafety[selected.id])
                context.stroke(TreemapPalette.shape(selected), with: .color(color), style: StrokeStyle(lineWidth: 2.5, dash: [5, 3]))
            }
            if let hovered, !hovered.isOverflow {
                let color = TreemapPalette.color(for: hovered, coloring: coloring, safety: tileSafety[hovered.id])
                let shape = TreemapPalette.shape(hovered)
                context.fill(shape, with: .color(color.opacity(0.14)))
                context.stroke(shape, with: .color(color), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }
}
