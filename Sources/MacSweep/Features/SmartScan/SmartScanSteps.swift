import SwiftUI

enum SmartScanStep: Int, CaseIterable, Identifiable {
    case junk, hidden, security, speed, apps

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .junk: "Junk & caches"
        case .hidden: "Hidden space & AI sessions"
        case .security: "Malware & security"
        case .speed: "Speed & startup"
        case .apps: "Apps & updates"
        }
    }

    var symbol: String {
        switch self {
        case .junk: "trash"
        case .hidden: "externaldrive.badge.questionmark"
        case .security: "checkmark.shield"
        case .speed: "hare"
        case .apps: "square.stack.3d.up"
        }
    }

    var tint: Color {
        switch self {
        case .junk: .green
        case .hidden: .teal
        case .security: .indigo
        case .speed: .orange
        case .apps: .blue
        }
    }
}

enum StepState: Equatable {
    case waiting
    case running(String)
    case done(String)
}

/// Live checklist under the hero: each step shows a spinner while running and a check when done.
struct SmartScanChecklist: View {
    let states: [SmartScanStep: StepState]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(SmartScanStep.allCases) { step in
                let state = states[step] ?? .waiting
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(step.tint.opacity(0.15)).frame(width: 30, height: 30)
                        switch state {
                        case .waiting: Image(systemName: step.symbol).foregroundStyle(.secondary)
                        case .running: ProgressView().controlSize(.small)
                        case .done: Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(step.tint)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .accessibilityHidden(true)
                    Text(step.title).fontWeight(.medium).frame(width: 210, alignment: .leading)
                    Group {
                        switch state {
                        case .waiting: Text("Waiting").foregroundStyle(.tertiary)
                        case .running(let detail): Text(detail).foregroundStyle(.secondary)
                        case .done(let summary): Text(summary).foregroundStyle(.primary)
                        }
                    }
                    .font(.callout.monospacedDigit())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.numericText())
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.background.opacity(state == .waiting ? 0.3 : 0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: 720)
        .animation(.snappy, value: states)
    }
}
