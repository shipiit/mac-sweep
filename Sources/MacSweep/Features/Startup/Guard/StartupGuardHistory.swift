import MacSweepCore
import SwiftUI

/// What the Startup Guard has detected, blocked and approved, newest first.
struct StartupGuardHistory: View {
    let events: [StartupGuardEvent]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "History", subtitle: "The last \(StartupGuardArchive.historyLimit) things the guard did")
                if events.isEmpty {
                    Text("No activity yet.").foregroundStyle(.secondary)
                }
                ForEach(events.prefix(30)) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(event.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .leading)
                        Text(event.action).font(.callout.weight(.medium))
                        Text(event.name).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if !event.path.isEmpty, FileManager.default.fileExists(atPath: event.path) {
                            Button("Reveal") { FileActions.reveal(event.path) }.controlSize(.small)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
