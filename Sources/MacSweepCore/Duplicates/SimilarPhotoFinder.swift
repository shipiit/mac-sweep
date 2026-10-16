import Foundation
import os
import Vision

public struct SimilarPhotoOptions: Sendable {
    public var walk: WalkOptions
    /// Hard cap per run so memory and the pairwise comparison stay bounded.
    public var maxImages = 5_000
    /// Feature-print distance at or below which two images count as near-duplicates.
    public var threshold: Float = SimilarPhotoFinder.defaultThreshold
    /// Images analysed at once. Vision already uses the Neural Engine/GPU internally.
    public var concurrency = 3
    public var preferredFolders: [String] = []

    public init() {
        walk = WalkOptions()
        walk.minimumSize = 8 * 1024
        walk.allowedExtensions = ["jpg", "jpeg", "heic", "png"]
    }
}

public struct PhotoCluster: Sendable, Identifiable, Equatable {
    /// Ranked: the first photo is the suggested one to keep.
    public let photos: [FileStat]

    public init(photos: [FileStat]) { self.photos = photos }

    public var id: String { photos.map(\.path).sorted().first ?? "" }
    public var suggestedKeep: FileStat? { photos.first }
    /// Space freed by keeping only the suggested photo.
    public var reclaimable: UInt64 { photos.dropFirst().reduce(0) { $0 + $1.size } }

    public func removing(_ paths: Set<String>) -> PhotoCluster? {
        let left = photos.filter { !paths.contains($0.path) }
        return left.count >= 2 ? PhotoCluster(photos: left) : nil
    }
}

public struct SimilarPhotoResult: Sendable, Equatable {
    public var clusters: [PhotoCluster]
    public var imagesAnalysed: Int
    /// True when more images were found than `maxImages`; only the most recent ones were analysed.
    public var wasCapped: Bool
    public var failed: Int
    public var skippedCloudOnly: Int
    public var rejectedRoots: [ScanRoots.Rejection]
}

/// Near-duplicate photos (bursts, edits, re-saves) via Vision feature prints.
public enum SimilarPhotoFinder {
    /// Vision revision 2 prints are unit length, so distances fall in 0…2. Calibrated on synthetic
    /// images only; real bursts may need a different value, which is why the UI exposes it.
    public static let defaultThreshold: Float = 0.45
    private static let log = Logger(subsystem: Log.subsystem, category: "photos")

    public static func find(
        roots: [String], home: String = NSHomeDirectory(), options: SimilarPhotoOptions = SimilarPhotoOptions(),
        progress: FinderProgress = FinderProgress()
    ) async throws -> SimilarPhotoResult {
        let resolution = ScanRoots.resolve(roots, home: home)
        progress.begin(.listing, total: 0)
        var stats = WalkStats()
        var images: [FileStat] = []
        var inodes = Set<String>()
        FileWalker.walk(roots: resolution.accepted, options: options.walk, stats: &stats, progress: progress) { file in
            if inodes.insert("\(file.device):\(file.inode)").inserted { images.append(file) }
            return true
        }
        progress.seen(stats.filesSeen)
        try Task.checkCancellation()

        let wasCapped = images.count > options.maxImages
        if wasCapped {
            images = Array(images.sorted { $0.modified > $1.modified }.prefix(options.maxImages))
        }

        progress.begin(.analyzing, total: images.count)
        let printed = await Concurrent.map(images, limit: options.concurrency) { image -> (FileStat, [Float])? in
            defer { progress.step() }
            guard !Task.isCancelled, let vector = featurePrint(image.path) else { return nil }
            return (image, vector)
        }
        try Task.checkCancellation()
        let analysed = printed.compactMap { $0 }

        progress.begin(.grouping, total: 0)
        let indexClusters = try PhotoClustering.clusters(vectors: analysed.map(\.1), threshold: options.threshold)
        let clusters = indexClusters
            .map { PhotoCluster(photos: KeepSuggestion.rankPhotos($0.map { analysed[$0].0 }, preferredFolders: options.preferredFolders)) }
            .sorted { $0.reclaimable != $1.reclaimable ? $0.reclaimable > $1.reclaimable : $0.id < $1.id }
        log.info("similar photos: \(analysed.count) analysed, \(clusters.count) clusters")
        return SimilarPhotoResult(
            clusters: clusters, imagesAnalysed: analysed.count, wasCapped: wasCapped, failed: images.count - analysed.count,
            skippedCloudOnly: stats.skippedCloudOnly, rejectedRoots: resolution.rejected
        )
    }

    /// The image's feature print copied into plain floats, so no Vision objects or pixels outlive the call.
    public static func featurePrint(_ path: String) -> [Float]? {
        autoreleasepool {
            let request = VNGenerateImageFeaturePrintRequest()
            request.revision = VNGenerateImageFeaturePrintRequestRevision2
            let handler = VNImageRequestHandler(url: URL(fileURLWithPath: path), options: [:])
            do {
                try handler.perform([request])
            } catch {
                log.notice("feature print failed for \(path, privacy: .private): \(error.localizedDescription, privacy: .public)")
                return nil
            }
            guard let observation = request.results?.first, observation.elementType == .float else { return nil }
            return observation.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(observation.elementCount)) }
        }
    }
}
