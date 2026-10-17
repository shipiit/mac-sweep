import SwiftUI
import UniformTypeIdentifiers

/// Shows the generated cleanup script to read, copy or save. MacSweep never runs it.
struct CleanupScriptSheet: View {
    let script: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleanup script").font(.title2.weight(.semibold))
            Text("Uses each tool's own clean command where one exists (npm, pnpm, brew, uv, docker…). Items marked REVIEW stay commented out. Nothing has been deleted.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(script).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let saveError { Label(saveError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            HStack {
                Button("Save…") { save() }
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    FileActions.copy(script)
                    copied = true
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 760, height: 520)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "macsweep-cleanup.sh"
        panel.allowedContentTypes = [.shellScript]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            saveError = nil
        } catch {
            saveError = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
