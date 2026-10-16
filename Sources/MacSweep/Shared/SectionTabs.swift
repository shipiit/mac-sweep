import SwiftUI

extension View {
    /// The one tab style used across MacSweep: a segmented control centred in the window toolbar, exactly like
    /// Processes & Memory (titles only, as macOS renders segmented labels as icons alone). Page actions go in `.primaryAction` toolbar items next to it.
    func sectionTabs<Tab: Hashable & Identifiable>(_ tabs: [Tab], selection: Binding<Tab>, title: @escaping (Tab) -> String) -> some View {
        toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: selection) {
                    ForEach(tabs) { tab in
                        Text(title(tab)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}
