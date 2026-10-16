import Foundation

/// A privacy permission macOS tracks in TCC.db, with the System Settings pane that manages it.
public struct TCCService: Identifiable, Sendable, Equatable {
    /// The raw TCC key, e.g. `kTCCServiceCamera`.
    public let key: String
    public let title: String
    public let symbol: String
    /// The `Privacy_…` anchor of the System Settings pane.
    public let paneAnchor: String
    /// Grants that let an app watch or control everything you do.
    public let isPowerful: Bool

    public var id: String { key }

    public var settingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?" + paneAnchor)
    }

    public init(key: String, title: String, symbol: String, paneAnchor: String, isPowerful: Bool = false) {
        self.key = key
        self.title = title
        self.symbol = symbol
        self.paneAnchor = paneAnchor
        self.isPowerful = isPowerful
    }
}

public enum TCCServiceCatalog {
    /// Display order in the audit: powerful grants first, then sensors, then personal data.
    public static let known: [TCCService] = [
        TCCService(key: "kTCCServiceAccessibility", title: "Accessibility", symbol: "accessibility",
                   paneAnchor: "Privacy_Accessibility", isPowerful: true),
        TCCService(key: "kTCCServiceSystemPolicyAllFiles", title: "Full Disk Access", symbol: "internaldrive",
                   paneAnchor: "Privacy_AllFiles", isPowerful: true),
        TCCService(key: "kTCCServiceScreenCapture", title: "Screen & System Audio Recording", symbol: "rectangle.dashed.badge.record",
                   paneAnchor: "Privacy_ScreenCapture", isPowerful: true),
        TCCService(key: "kTCCServiceListenEvent", title: "Input Monitoring", symbol: "keyboard",
                   paneAnchor: "Privacy_ListenEvent", isPowerful: true),
        TCCService(key: "kTCCServicePostEvent", title: "Control Keyboard & Mouse", symbol: "cursorarrow.click.2",
                   paneAnchor: "Privacy_Accessibility", isPowerful: true),
        TCCService(key: "kTCCServiceAppleEvents", title: "Automation", symbol: "gearshape.2", paneAnchor: "Privacy_Automation"),
        TCCService(key: "kTCCServiceSystemPolicyAppBundles", title: "App Management", symbol: "app.badge", paneAnchor: "Privacy_AppBundles"),
        TCCService(key: "kTCCServiceDeveloperTool", title: "Developer Tools", symbol: "hammer", paneAnchor: "Privacy_DevTools"),
        TCCService(key: "kTCCServiceCamera", title: "Camera", symbol: "camera", paneAnchor: "Privacy_Camera"),
        TCCService(key: "kTCCServiceMicrophone", title: "Microphone", symbol: "mic", paneAnchor: "Privacy_Microphone"),
        TCCService(key: "kTCCServiceAudioCapture", title: "System Audio Recording", symbol: "waveform", paneAnchor: "Privacy_AudioCapture"),
        TCCService(key: "kTCCServiceSpeechRecognition", title: "Speech Recognition", symbol: "waveform.and.mic",
                   paneAnchor: "Privacy_SpeechRecognition"),
        TCCService(key: "kTCCServiceBluetoothAlways", title: "Bluetooth", symbol: "dot.radiowaves.left.and.right", paneAnchor: "Privacy_Bluetooth"),
        TCCService(key: "kTCCServiceLocation", title: "Location Services", symbol: "location", paneAnchor: "Privacy_LocationServices"),
        TCCService(key: "kTCCServicePhotos", title: "Photos", symbol: "photo.on.rectangle", paneAnchor: "Privacy_Photos"),
        TCCService(key: "kTCCServiceAddressBook", title: "Contacts", symbol: "person.crop.circle", paneAnchor: "Privacy_Contacts"),
        TCCService(key: "kTCCServiceCalendar", title: "Calendars", symbol: "calendar", paneAnchor: "Privacy_Calendars"),
        TCCService(key: "kTCCServiceReminders", title: "Reminders", symbol: "checklist", paneAnchor: "Privacy_Reminders"),
        TCCService(key: "kTCCServiceMediaLibrary", title: "Media & Apple Music", symbol: "music.note", paneAnchor: "Privacy_Media"),
        TCCService(key: "kTCCServiceSystemPolicyDesktopFolder", title: "Desktop Folder", symbol: "menubar.dock.rectangle",
                   paneAnchor: "Privacy_FilesAndFolders"),
        TCCService(key: "kTCCServiceSystemPolicyDocumentsFolder", title: "Documents Folder", symbol: "doc",
                   paneAnchor: "Privacy_FilesAndFolders"),
        TCCService(key: "kTCCServiceSystemPolicyDownloadsFolder", title: "Downloads Folder", symbol: "arrow.down.circle",
                   paneAnchor: "Privacy_FilesAndFolders"),
        TCCService(key: "kTCCServiceSystemPolicyNetworkVolumes", title: "Network Volumes", symbol: "externaldrive.connected.to.line.below",
                   paneAnchor: "Privacy_FilesAndFolders"),
        TCCService(key: "kTCCServiceSystemPolicyRemovableVolumes", title: "Removable Volumes", symbol: "externaldrive",
                   paneAnchor: "Privacy_FilesAndFolders"),
    ]

    private static let byKey = Dictionary(uniqueKeysWithValues: known.map { ($0.key, $0) })

    public static func service(for key: String) -> TCCService? { byKey[key] }

    /// Internal services (iCloud, file providers, …) a user can't manage directly; grouped under "Other".
    public static func fallback(for key: String) -> TCCService {
        let name = key.hasPrefix("kTCCService") ? String(key.dropFirst("kTCCService".count)) : key
        return TCCService(key: key, title: name.isEmpty ? "Other" : name, symbol: "lock", paneAnchor: "Privacy")
    }

    public static func order(of key: String) -> Int {
        known.firstIndex { $0.key == key } ?? known.count
    }
}
