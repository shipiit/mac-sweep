import Foundation

/// Picks out superseded versions in folders that keep several, such as CLI version stores and editor extensions.
public enum VersionedFolders {
    /// Numeric dotted comparison: "2.1.120" > "2.1.119" > "2.1.99". Non-numeric parts compare as text.
    public static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let left = lhs.split(whereSeparator: { $0 == "." || $0 == "-" })
        let right = rhs.split(whereSeparator: { $0 == "." || $0 == "-" })
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? String(left[index]) : "0"
            let b = index < right.count ? String(right[index]) : "0"
            if let x = Int(a), let y = Int(b) {
                if x != y { return x > y }
            } else if a != b {
                return a > b
            }
        }
        return false
    }

    static func looksLikeVersion(_ name: String) -> Bool {
        name.first?.isNumber == true && name.contains(".")
    }

    /// Version-named entries to remove, keeping the newest `keep`.
    public static func olderVersions(_ names: [String], keep: Int) -> [String] {
        let versions = names.filter(looksLikeVersion).sorted { isNewer($0, than: $1) }
        return Array(versions.dropFirst(max(keep, 1)))
    }

    /// "publisher.name-1.2.3" or "publisher.name-1.2.3-darwin-arm64" → ("publisher.name", "1.2.3-darwin-arm64").
    static func splitExtension(_ name: String) -> (id: String, version: String)? {
        guard let range = name.range(of: #"-\d+\.\d+"#, options: .regularExpression) else { return nil }
        return (String(name[..<range.lowerBound]), String(name[name.index(after: range.lowerBound)...]))
    }

    /// For each extension installed more than once (same platform suffix), every folder but the newest.
    public static func duplicateExtensions(_ names: [String]) -> [String] {
        var groups: [String: [(name: String, version: String)]] = [:]
        for name in names {
            guard let parts = splitExtension(name) else { continue }
            let platform = parts.version.split(separator: "-").dropFirst().joined(separator: "-")
            groups[parts.id + "|" + platform, default: []].append((name, parts.version))
        }
        return groups.values.flatMap { versions -> [String] in
            guard versions.count > 1 else { return [] }
            return versions.sorted { isNewer($0.version, than: $1.version) }.dropFirst().map(\.name)
        }
        .sorted()
    }
}
