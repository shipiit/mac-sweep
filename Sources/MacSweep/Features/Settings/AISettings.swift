import MacSweepCore
import SwiftUI

struct AISettings: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKeys.claudePlanLimits) private var planLimits = false
    @AppStorage(SettingsKeys.aiDefaultTool) private var defaultTool: AIProvider = .claudeCode

    var body: some View {
        Form {
            Section("Menu bar & notch") {
                Picker("Show limits for", selection: $defaultTool) {
                    ForEach(AIProvider.allCases) { Text($0.rawValue).tag($0) }
                }
                Text("The menu bar AI tile and the notch show this tool's 5-hour and weekly limits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Claude plan limits") {
                Toggle("Show real Claude plan limits", isOn: $planLimits)
                    .onChange(of: planLimits) { Task { await app.ai.refreshPlan(force: true) } }
                Text("Reads Claude Code's sign-in from your Keychain (macOS asks you to allow it) and asks Anthropic for your session, weekly and per-model limits. Read-only: MacSweep reads it once per launch, keeps it only in memory, and never refreshes, stores or sends it anywhere else. Choose Always Allow so macOS doesn't ask again. Off: Claude shows 5-hour block time from your transcripts instead.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if planLimits { status }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var status: some View {
        switch (app.ai.planUsage, app.ai.planError) {
        case (_, .notSignedIn?):
            Label("Claude Code isn't signed in on this Mac.", systemImage: "person.crop.circle.badge.questionmark").foregroundStyle(.orange)
        case (_, .denied?):
            Label("Keychain access was denied, so MacSweep stopped asking. Turn this off and on to try again, and choose Always Allow.",
                  systemImage: "hand.raised").foregroundStyle(.orange)
        case (_, .expired?):
            Label("Sign-in expired. Run Claude Code once to refresh it, then try again.", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange)
        case (_, .unavailable?):
            Label("Couldn't reach Anthropic. Will retry in a few minutes.", systemImage: "wifi.exclamationmark").foregroundStyle(.orange)
        case (let usage?, nil):
            Label("Connected\(usage.plan.map { " · \($0)" } ?? "")", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case (nil, nil):
            Label("Checking…", systemImage: "hourglass").foregroundStyle(.secondary)
        }
    }
}
