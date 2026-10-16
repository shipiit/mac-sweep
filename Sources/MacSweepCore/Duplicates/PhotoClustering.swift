import Accelerate
import Foundation

/// Groups near-identical images from pairwise feature-print distances. Pure: the distances come in
/// from outside, so the grouping rules are testable without Vision or real photos.
public enum PhotoClustering {
    /// Euclidean distance, the metric Vision's feature prints are compared with.
    public static func distance(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return .infinity }
        var squared: Float = 0
        vDSP_distancesq(lhs, 1, rhs, 1, &squared, vDSP_Length(lhs.count))
        return squared.squareRoot()
    }

    /// Indices joined whenever two items are within `threshold` (single linkage), so a burst whose
    /// neighbouring shots are each close ends up as one group. Only groups of two or more are
    /// returned, each sorted, ordered by their first index.
    public static func clusters(count: Int, threshold: Float, distance: (Int, Int) -> Float) throws -> [[Int]] {
        guard count > 1 else { return [] }
        var parent = Array(0..<count)

        func root(_ index: Int) -> Int {
            var node = index
            while parent[node] != node {
                parent[node] = parent[parent[node]]
                node = parent[node]
            }
            return node
        }

        for row in 0..<count {
            try Task.checkCancellation()
            for column in (row + 1)..<count where distance(row, column) <= threshold {
                let lhs = root(row)
                let rhs = root(column)
                if lhs != rhs { parent[max(lhs, rhs)] = min(lhs, rhs) }
            }
        }

        var members: [Int: [Int]] = [:]
        for index in 0..<count { members[root(index), default: []].append(index) }
        return members.values.filter { $0.count > 1 }.map { $0.sorted() }.sorted { $0[0] < $1[0] }
    }

    /// Clusters feature vectors directly.
    public static func clusters(vectors: [[Float]], threshold: Float) throws -> [[Int]] {
        try clusters(count: vectors.count, threshold: threshold) { distance(vectors[$0], vectors[$1]) }
    }
}
