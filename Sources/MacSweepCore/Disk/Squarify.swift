import CoreGraphics

/// Squarified treemap layout (Bruls, Huizing, van Wijk). Keeps tiles as close to square as possible.
public enum Squarify {
    /// Returns one rect per input value, in input order. Non-positive values get `.zero`.
    public static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: values.count)
        let total = values.filter { $0 > 0 }.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }

        let scale = Double(rect.width * rect.height) / total
        let order = values.indices.filter { values[$0] > 0 }.sorted { values[$0] > values[$1] }
        let areas = Dictionary(uniqueKeysWithValues: order.map { ($0, values[$0] * scale) })

        var remaining = rect
        var row: [Int] = []
        var next = 0
        while next < order.count {
            let side = Double(min(remaining.width, remaining.height))
            let candidate = row + [order[next]]
            if row.isEmpty || worst(candidate, areas, side) <= worst(row, areas, side) {
                row = candidate
                next += 1
            } else {
                remaining = place(row, areas, in: remaining, into: &result)
                row = []
            }
        }
        if !row.isEmpty { _ = place(row, areas, in: remaining, into: &result) }
        return result
    }

    private static func worst(_ row: [Int], _ areas: [Int: Double], _ side: Double) -> Double {
        let values = row.compactMap { areas[$0] }
        let sum = values.reduce(0, +)
        guard sum > 0, side > 0, let maxArea = values.max(), let minArea = values.min() else { return .infinity }
        let sideSquared = side * side
        let sumSquared = sum * sum
        return max(sideSquared * maxArea / sumSquared, sumSquared / (sideSquared * minArea))
    }

    private static func place(
        _ row: [Int], _ areas: [Int: Double], in rect: CGRect, into result: inout [CGRect]
    ) -> CGRect {
        let sum = row.compactMap { areas[$0] }.reduce(0, +)
        if rect.width >= rect.height {
            let width = CGFloat(sum / Double(rect.height))
            var y = rect.minY
            for index in row {
                let height = CGFloat((areas[index] ?? 0) / Double(width))
                result[index] = CGRect(x: rect.minX, y: y, width: width, height: height)
                y += height
            }
            return CGRect(x: rect.minX + width, y: rect.minY, width: max(rect.width - width, 0), height: rect.height)
        } else {
            let height = CGFloat(sum / Double(rect.width))
            var x = rect.minX
            for index in row {
                let width = CGFloat((areas[index] ?? 0) / Double(height))
                result[index] = CGRect(x: x, y: rect.minY, width: width, height: height)
                x += width
            }
            return CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: max(rect.height - height, 0))
        }
    }
}
