import SwiftUI

/// Rows of fixed column count where every card in a row stretches to the tallest one,
/// so cards line up cleanly (LazyVGrid sizes each cell to its own content).
struct EqualHeightGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    var columns = 3
    var spacing: CGFloat = 14
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow(alignment: .top) {
                    ForEach(row) { item in
                        cell(item).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    // Keep column widths equal on a short final row.
                    ForEach(0..<(columns - row.count), id: \.self) { _ in Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                }
            }
        }
    }

    private var rows: [[Item]] {
        stride(from: 0, to: items.count, by: max(columns, 1)).map { Array(items[$0..<min($0 + columns, items.count)]) }
    }
}
