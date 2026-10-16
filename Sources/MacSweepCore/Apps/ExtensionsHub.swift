import Foundation

public struct SystemExtensionItem: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case quickLook = "Quick Look plugins"
        case spotlight = "Spotlight importers"
        case preferencePane = "Preference panes"
        case internetPlugin = "Internet plug-ins"
        case service = "Services"
        case audioPlugin = "Audio plug-ins"
    }

    public let name: String
    public let kind: Kind
    public let path: String
    public let isUserInstalled: Bool

    public var id: String { path }
}

/// Third-party add-ons that load into macOS or other apps. Removing them goes through the Trash.
public enum ExtensionsHub {
    static let locations: [(SystemExtensionItem.Kind, String, String)] = [
        (.quickLook, "Library/QuickLook", "qlgenerator"),
        (.spotlight, "Library/Spotlight", "mdimporter"),
        (.preferencePane, "Library/PreferencePanes", "prefPane"),
        (.internetPlugin, "Library/Internet Plug-Ins", "plugin"),
        (.service, "Library/Services", "workflow"),
        (.audioPlugin, "Library/Audio/Plug-Ins/Components", "component"),
    ]

    public static func scan(home: String = NSHomeDirectory()) -> [SystemExtensionItem] {
        var items: [SystemExtensionItem] = []
        for (kind, relative, ext) in locations {
            for (base, isUser) in [(home + "/" + relative, true), ("/" + relative, false)] {
                for entry in (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? [] where entry.hasSuffix("." + ext) {
                    items.append(SystemExtensionItem(name: (entry as NSString).deletingPathExtension, kind: kind,
                                                     path: base + "/" + entry, isUserInstalled: isUser))
                }
            }
        }
        return items.sorted { ($0.kind.rawValue, $0.name) < ($1.kind.rawValue, $1.name) }
    }
}
