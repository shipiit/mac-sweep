import CoreGraphics
import MacSweepCore

struct TreemapTile: Identifiable {
    let node: FileNode
    let rect: CGRect
    /// 0 = child of the focused folder, 1 = grandchild drawn inside its parent.
    let depth: Int
    let category: StorageCategory
    let hasNested: Bool
    /// Synthetic tile representing the long tail of entries too small to draw individually.
    let isOverflow: Bool

    var id: String { node.id + (isOverflow ? "#overflow" : "") }
}

enum TreemapLayout {
    static let gap: CGFloat = 3
    static let headerHeight: CGFloat = 24
    static let maxTopLevel = 60
    static let maxNested = 24

    static func tiles(for focus: FileNode, in bounds: CGRect, home: String) -> [TreemapTile] {
        let inherited = category(for: focus, home: home, inherited: .other)
        var tiles: [TreemapTile] = []
        for (node, rect, overflow) in place(focus.children, in: bounds, limit: maxTopLevel, parent: focus) {
            let tileRect = rect.insetBy(dx: gap / 2, dy: gap / 2)
            guard tileRect.width > 2, tileRect.height > 2 else { continue }
            let cat = overflow ? inherited : category(for: node, home: home, inherited: inherited)
            let canNest = !overflow && node.isDirectory && !node.children.isEmpty
                && tileRect.width > 110 && tileRect.height > 90
            tiles.append(TreemapTile(node: node, rect: tileRect, depth: 0, category: cat, hasNested: canNest, isOverflow: overflow))
            guard canNest else { continue }

            let inner = CGRect(
                x: tileRect.minX + 6, y: tileRect.minY + headerHeight,
                width: tileRect.width - 12, height: tileRect.height - headerHeight - 6
            )
            for (child, childRect, childOverflow) in place(node.children, in: inner, limit: maxNested, parent: node) {
                let nested = childRect.insetBy(dx: 2, dy: 2)
                guard nested.width > 3, nested.height > 3 else { continue }
                let childCategory = childOverflow ? cat : category(for: child, home: home, inherited: cat)
                tiles.append(TreemapTile(node: child, rect: nested, depth: 1, category: childCategory, hasNested: false, isOverflow: childOverflow))
            }
        }
        return tiles
    }

    /// Lays out the biggest `limit` entries and folds the remainder into one overflow tile.
    private static func place(
        _ nodes: [FileNode], in rect: CGRect, limit: Int, parent: FileNode
    ) -> [(FileNode, CGRect, Bool)] {
        let visible = Array(nodes.filter { $0.size > 0 }.prefix(limit))
        let restSize = nodes.filter { $0.size > 0 }.dropFirst(limit).reduce(0) { $0 + $1.size }
        var values = visible.map { Double($0.size) }
        if restSize > 0 { values.append(Double(restSize)) }
        let rects = Squarify.layout(values, in: rect)

        var placed = zip(visible, rects).map { ($0, $1, false) }
        if restSize > 0, let last = rects.last {
            let hidden = nodes.count - visible.count
            let overflow = FileNode(path: parent.path, name: "\(hidden) more", kind: .aggregate, size: restSize, itemCount: hidden)
            placed.append((overflow, last, true))
        }
        return placed
    }

    static func category(for node: FileNode, home: String, inherited: StorageCategory) -> StorageCategory {
        StorageCategory.classify(path: node.path, home: home, isGitRepo: node.isGitRepo) ?? inherited
    }

    static func hitTest(_ tiles: [TreemapTile], at point: CGPoint) -> TreemapTile? {
        tiles.last { $0.rect.contains(point) }
    }
}
