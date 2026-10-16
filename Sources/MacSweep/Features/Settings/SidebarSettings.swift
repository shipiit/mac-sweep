import SwiftUI

/// Choose which pages appear in the sidebar. Hidden pages stay reachable from Settings and keep working in the background.
struct SidebarSettings: View {
    @AppStorage(SettingsKeys.hiddenSections) private var hiddenRaw = ""

    var body: some View {
        let hidden = SidebarVisibility.hidden(hiddenRaw)
        Form {
            Section {
                Text("Turn off pages you don't use to keep the sidebar short. Smart Scan and Dashboard always stay.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Show All") { hiddenRaw = "" }.disabled(hidden.isEmpty)
            }
            ForEach(SidebarSection.groups, id: \.title) { group in
                Section(group.title.isEmpty ? "Main" : group.title) {
                    ForEach(group.sections) { section in
                        Toggle(isOn: Binding(get: { !hidden.contains(section) }, set: { isOn in
                            hiddenRaw = SidebarVisibility.encode(isOn ? hidden.subtracting([section]) : hidden.union([section]))
                        })) {
                            Label(section.rawValue, systemImage: section.symbol)
                        }
                        .disabled(SidebarVisibility.alwaysShown.contains(section))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

enum SidebarVisibility {
    static let alwaysShown: Set<SidebarSection> = [.smartScan, .overview]

    static func hidden(_ raw: String) -> Set<SidebarSection> {
        Set(raw.split(separator: ",").compactMap { SidebarSection(rawValue: String($0)) }).subtracting(alwaysShown)
    }

    static func encode(_ sections: Set<SidebarSection>) -> String {
        sections.subtracting(alwaysShown).map(\.rawValue).sorted().joined(separator: ",")
    }
}
