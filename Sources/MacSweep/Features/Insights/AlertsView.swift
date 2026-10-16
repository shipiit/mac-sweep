import MacSweepCore
import SwiftUI

struct AlertsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let insights = app.insights
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                StatStrip {
                    StatTile(title: "Watching", value: "\(insights.enabledRules.count) of \(AlertRule.allCases.count)", detail: "rules on")
                    StatTile(title: "Last 24 hours", value: "\(insights.recent.filter { $0.date > Date().addingTimeInterval(-86_400) }.count)", detail: "alerts")
                    StatTile(title: "Critical", value: "\(insights.recent.filter { $0.severity == .critical }.count)", detail: "in recent alerts",
                             dot: insights.recent.contains { $0.severity == .critical } ? .red : .green)
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionHeader(title: "Recent alerts", subtitle: "Checked every 30 seconds in the background")
                            Spacer()
                            if !insights.recent.isEmpty { Button("Clear") { insights.clearRecent() } }
                        }
                        if insights.recent.isEmpty {
                            Label("All quiet. You'll get a notification when something needs attention.", systemImage: "checkmark.seal")
                                .foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                        ForEach(insights.recent) { alert in AlertRow(alert: alert) }
                    }
                }
                SectionHeader(title: "What to watch", subtitle: "Each alert fires once, then waits until the condition clears or a cooldown passes")
                EqualHeightGrid(items: AlertRule.allCases, columns: 2) { rule in RuleCard(rule: rule, insights: insights) }
            }
            .padding(20)
        }
        .navigationTitle("Smart Alerts")
    }
}

private struct RuleCard: View {
    let rule: AlertRule
    let insights: InsightsCenter
    @Environment(\.appAccent) private var accent

    var body: some View {
        let isOn = insights.enabledRules.contains(rule)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: rule.symbol).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOn ? accent : .secondary)
                .frame(width: 34, height: 34)
                .background((isOn ? accent : Color.secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.title).fontWeight(.semibold)
                Text(rule.explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(rule.title, isOn: Binding(get: { isOn }, set: { value in
                if value { insights.enabledRules.insert(rule) } else { insights.enabledRules.remove(rule) }
            }))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}

private struct AlertRow: View {
    let alert: SmartAlert

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: alert.rule.symbol).foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(alert.title).fontWeight(.semibold)
                    Pill(text: alert.severity.rawValue.capitalized, color: color)
                }
                Text(alert.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(Format.relative(alert.date)).font(.caption).foregroundStyle(.secondary)
            if let path = alert.subjectPath {
                Button { FileActions.reveal(path) } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless).help("Reveal in Finder").accessibilityLabel("Reveal \(path)")
            }
        }
        .padding(.vertical, 4)
    }

    private var color: Color {
        switch alert.severity {
        case .critical: .red
        case .warning: .orange
        case .info: .blue
        }
    }
}
