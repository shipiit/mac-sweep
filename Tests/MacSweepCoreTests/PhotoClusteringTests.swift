import AppKit
import Foundation
import Testing
@testable import MacSweepCore

@Suite struct PhotoClusteringTests {
    /// Distances for points on a line: |a - b|.
    private func line(_ positions: [Float]) -> (Int, Int) -> Float {
        { abs(positions[$0] - positions[$1]) }
    }

    @Test func clustersWithinThreshold() throws {
        let positions: [Float] = [0, 0.1, 5, 5.05, 10]
        let clusters = try PhotoClustering.clusters(count: positions.count, threshold: 0.2, distance: line(positions))
        #expect(clusters == [[0, 1], [2, 3]])
    }

    @Test func thresholdIsInclusiveAndTunable() throws {
        let positions: [Float] = [0, 0.5, 1.0]
        #expect(try PhotoClustering.clusters(count: 3, threshold: 0.49, distance: line(positions)).isEmpty)
        #expect(try PhotoClustering.clusters(count: 3, threshold: 0.5, distance: line(positions)) == [[0, 1, 2]])
        #expect(try PhotoClustering.clusters(count: 3, threshold: 2, distance: line(positions)) == [[0, 1, 2]])
    }

    @Test func singleLinkageChainsBursts() throws {
        // Each shot is close to the next though the ends are far apart: one burst.
        let positions: [Float] = [0, 0.3, 0.6, 0.9, 5]
        #expect(try PhotoClustering.clusters(count: 5, threshold: 0.35, distance: line(positions)) == [[0, 1, 2, 3]])
    }

    @Test func edgeCounts() throws {
        #expect(try PhotoClustering.clusters(count: 0, threshold: 1) { _, _ in 0 }.isEmpty)
        #expect(try PhotoClustering.clusters(count: 1, threshold: 1) { _, _ in 0 }.isEmpty)
        #expect(try PhotoClustering.clusters(vectors: [], threshold: 1).isEmpty)
    }

    @Test func vectorDistance() throws {
        #expect(PhotoClustering.distance([0, 0], [3, 4]) == 5)
        #expect(PhotoClustering.distance([1, 2, 3], [1, 2, 3]) == 0)
        #expect(PhotoClustering.distance([1], [1, 2]) == .infinity)
        #expect(PhotoClustering.distance([], []) == .infinity)
        let clusters = try PhotoClustering.clusters(vectors: [[0, 0], [0.1, 0], [3, 3], [1, 2]], threshold: 0.2)
        #expect(clusters == [[0, 1]])
    }

    @Test func cancellationThrows() async {
        let task = Task { try PhotoClustering.clusters(count: 10, threshold: 1) { _, _ in 0 } }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func photoRankingKeepsTheBiggest() {
        let date = Date(timeIntervalSince1970: 0)
        let small = FileStat(path: "/p/a.jpg", size: 100, device: 1, inode: 1, modified: date, created: date)
        let big = FileStat(path: "/p/b.jpg", size: 900, device: 1, inode: 2, modified: date, created: date)
        #expect(KeepSuggestion.rankPhotos([small, big], preferredFolders: []).first == big)
    }

    // MARK: Vision on generated images

    private func writeImage(_ path: String, quality: Double, draw: (CGContext) -> Void) throws {
        let size = 256
        let context = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        draw(context)
        let image = try #require(context.makeImage())
        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: quality]))
        try Fixtures.write(path, bytes: 0)
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func scene(_ shift: CGFloat) -> (CGContext) -> Void {
        { context in
            context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            context.setFillColor(CGColor(red: 0.95, green: 0.8, blue: 0.1, alpha: 1))
            context.fillEllipse(in: CGRect(x: 60 + shift, y: 60, width: 120, height: 120))
        }
    }

    private func stripes(_ context: CGContext) {
        for index in 0..<16 {
            context.setFillColor(index.isMultiple(of: 2) ? CGColor(red: 0, green: 0, blue: 0, alpha: 1) : CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: index * 16, y: 0, width: 16, height: 256))
        }
    }

    @Test func similarPhotoFinderGroupsNearDuplicates() async throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let pics = home + "/Pictures"
        try writeImage(pics + "/shot1.jpg", quality: 0.9, draw: scene(0))
        try writeImage(pics + "/shot2.jpg", quality: 0.5, draw: scene(4))
        try writeImage(pics + "/other.jpg", quality: 0.9, draw: stripes)

        var options = SimilarPhotoOptions()
        options.walk.minimumSize = 1
        let result = try await SimilarPhotoFinder.find(roots: [pics], home: home, options: options)
        #expect(result.imagesAnalysed == 3)
        #expect(result.clusters.count == 1)
        #expect(Set(result.clusters.first?.photos.map(\.path) ?? []) == [pics + "/shot1.jpg", pics + "/shot2.jpg"])

        options.maxImages = 2
        let capped = try await SimilarPhotoFinder.find(roots: [pics], home: home, options: options)
        #expect(capped.wasCapped && capped.imagesAnalysed == 2)
    }
}
