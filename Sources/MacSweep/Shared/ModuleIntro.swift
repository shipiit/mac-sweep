import SwiftUI

/// CleanMyMac-style landing page for a module: what it does, two benefits, one primary action.
struct ModuleIntro: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let bullets: [(symbol: String, title: String, detail: String)]
    let actionTitle: String
    var isWorking = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 50) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.system(size: 34, weight: .bold))
                    Text(subtitle).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(bullets, id: \.title) { bullet in
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: bullet.symbol).font(.system(size: 26, weight: .light)).foregroundStyle(tint)
                            .frame(width: 40).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(bullet.title).font(.headline)
                            Text(bullet.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Button(action: action) {
                    HStack {
                        if isWorking { ProgressView().controlSize(.small) }
                        Text(actionTitle).font(.title3.weight(.semibold))
                    }
                    .padding(.horizontal, 18).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .controlSize(.large)
                .disabled(isWorking)
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: 480, alignment: .leading)
            ZStack {
                Circle().fill(tint).frame(width: 260, height: 260)
                Circle().strokeBorder(.white.opacity(0.25), lineWidth: 10).frame(width: 260, height: 260)
                Image(systemName: symbol).font(.system(size: 110, weight: .medium)).foregroundStyle(.white)
            }
            .accessibilityHidden(true)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
