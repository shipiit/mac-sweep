import Foundation

enum FirefoxExtensions {
    static func scan(home: String) -> [BrowserExtension] {
        let root = home + "/Library/Application Support/Firefox/Profiles"
        let profiles = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        return profiles.flatMap { profile -> [BrowserExtension] in
            guard let data = FileManager.default.contents(atPath: root + "/" + profile + "/extensions.json") else { return [] }
            return parse(data, profile: profile, profileDir: root + "/" + profile)
        }
    }

    /// Parses Firefox's extensions.json, keeping user-installed add-ons only (no built-in system add-ons).
    static func parse(_ data: Data, profile: String, profileDir: String) -> [BrowserExtension] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let addons = json["addons"] as? [[String: Any]]
        else { return [] }
        return addons.compactMap { addon in
            guard addon["location"] as? String == "app-profile", addon["type"] as? String == "extension",
                  let id = addon["id"] as? String
            else { return nil }
            let locale = addon["defaultLocale"] as? [String: Any]
            let user = addon["userPermissions"] as? [String: Any]
            let permissions = (user?["permissions"] as? [String] ?? []) + (user?["origins"] as? [String] ?? [])
            let source = addon["sourceURI"] as? String ?? ""
            let signed = (addon["signedState"] as? Int ?? 0) >= 2
            return BrowserExtension(browser: "Firefox", profile: profile, extensionID: id,
                                    name: locale?["name"] as? String ?? id, version: addon["version"] as? String ?? "",
                                    permissions: permissions, path: addon["path"] as? String ?? profileDir,
                                    fromStore: signed || source.contains("addons.mozilla.org"))
        }
    }
}

public enum SafariExtensions {
    public static func scan() async -> [BrowserExtension] {
        guard let result = try? await Shell.run("/usr/bin/pluginkit", ["-mAvvv", "-p", "com.apple.Safari.web-extension"]) else { return [] }
        return parse(result.stdout)
    }

    /// Parses `pluginkit -mAvvv` blocks: "id(version)" then indented "Key = Value" lines.
    public static func parse(_ output: String) -> [BrowserExtension] {
        var results: [BrowserExtension] = []
        var current: (id: String, version: String, fields: [String: String])?

        func flush() {
            guard let block = current, let path = block.fields["Path"] else { return }
            let manifest = FileManager.default.contents(atPath: path + "/Contents/Resources/manifest.json")
                .flatMap { BrowserExtensions.parseManifest($0) }
            let parent = block.fields["Parent Bundle"] ?? path
            let fromStore = FileManager.default.fileExists(atPath: parent + "/Contents/_MASReceipt/receipt")
            results.append(BrowserExtension(
                browser: "Safari", profile: "Default", extensionID: block.id,
                name: block.fields["Display Name"] ?? manifest?.name ?? block.id, version: block.version,
                permissions: manifest?.permissions ?? [], path: path, iconPath: nil, fromStore: fromStore || manifest == nil
            ))
        }

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let equals = line.range(of: " = ") {
                current?.fields[String(line[..<equals.lowerBound])] = String(line[equals.upperBound...])
            } else if let open = line.lastIndex(of: "("), line.hasSuffix(")") {
                flush()
                let id = line[..<open].trimmingCharacters(in: CharacterSet(charactersIn: "+-! "))
                current = (id, String(line[line.index(after: open)..<line.index(before: line.endIndex)]), [:])
            }
        }
        flush()
        return results
    }
}
