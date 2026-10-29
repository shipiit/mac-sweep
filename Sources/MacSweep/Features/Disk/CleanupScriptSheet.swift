import MacSweepCore
import SwiftUI
import UniformTypeIdentifiers

/// Shows the generated cleanup script to read, copy or save, and can run the tool-managed part (npm, pnpm, brew…)
/// for you with a live log. Plain `rm` lines are never run from here; Clean… moves those to the Trash.
struct CleanupScriptSheet: View {
    let script: String
    let commands: [ToolCleanCommands.Command]
    let onFinished: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var saveError: String?
    @State private var log: [String] = []
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleanup script").font(.title2.weight(.semibold))
            Text("Uses each tool's own clean command where one exists (npm, pnpm, brew, uv, docker…). Items marked REVIEW stay commented out. Nothing has been deleted.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(log.isEmpty ? script : log.joined(separator: "\n")).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .defaultScrollAnchor(log.isEmpty ? .top : .bottom)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let saveError { Label(saveError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            HStack {
                Button("Save…") { save() }
                Button(copied ? "Copied" : "Copy") {
                    FileActions.copy(script)
                    copied = true
                }
                Spacer()
                if !commands.isEmpty {
                    Button {
                        Task { await runAll() }
                    } label: {
                        Label(isRunning ? "Running…" : "Run \(commands.count) tool command\(commands.count == 1 ? "" : "s")", systemImage: "play.fill")
                    }
                    .disabled(isRunning)
                    .help(commands.map(\.command).joined(separator: "\n"))
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).disabled(isRunning)
            }
        }
        .padding(20)
        .frame(width: 760, height: 540)
    }

    private func runAll() async {
        isRunning = true
        log = []
        for command in commands {
            log.append("$ \(command.command)")
            let outcome = await ToolCommandRunner.run(command) { line in Task { @MainActor in log.append(line) } }
            switch outcome {
            case .finished(let status): log.append(status == 0 ? "✓ done" : "✗ exited with \(status)")
            case .toolMissing: log.append("– \(command.tool) isn't installed, skipped")
            case .timedOut: log.append("✗ stopped after 10 minutes")
            }
            log.append("")
        }
        log.append("Finished. Re-measuring junk…")
        isRunning = false
        onFinished()
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
