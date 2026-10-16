import AppKit
import SwiftUI

enum FileActions {
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func open(url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Caches app and file icons; NSWorkspace icon lookups are too slow to repeat per table row render.
@MainActor
final class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()

    func icon(forPID pid: Int32, path: String?) -> NSImage {
        let key = "pid:\(pid):\(path ?? "")" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NSRunningApplication(processIdentifier: pid)?.icon
            ?? path.map { NSWorkspace.shared.icon(forFile: appBundle(for: $0) ?? $0) }
            ?? NSWorkspace.shared.icon(for: .unixExecutable)
        cache.setObject(image, forKey: key)
        return image
    }

    func icon(forFile path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: key)
        return image
    }

    /// Helpers inside an .app show the parent app's icon, which is what users recognise.
    private func appBundle(for path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }
}

struct FileIcon: View {
    let path: String
    var size: CGFloat = 16

    var body: some View {
        Image(nsImage: IconCache.shared.icon(forFile: path))
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct ProcessIcon: View {
    let pid: Int32
    let path: String?
    var size: CGFloat = 16

    var body: some View {
        Image(nsImage: IconCache.shared.icon(forPID: pid, path: path))
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
