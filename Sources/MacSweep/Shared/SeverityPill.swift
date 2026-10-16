import MacSweepCore
import SwiftUI

extension FindingSeverity {
    /// Shape differs per level so severity never depends on colour alone.
    var symbol: String {
        switch self {
        case .info: "checkmark.circle.fill"
        case .low: "info.circle.fill"
        case .medium: "exclamationmark.triangle.fill"
        case .high: "exclamationmark.octagon.fill"
        }
    }

    var label: String {
        switch self {
        case .info: "OK"
        case .low: "Low risk"
        case .medium: "Medium risk"
        case .high: "High risk"
        }
    }
}

/// Icon + text severity badge in the same capsule style as `Pill`.
struct SeverityPill: View {
    let severity: FindingSeverity
    var text: String? = nil

    var body: some View {
        Label(text ?? severity.label, systemImage: severity.symbol)
            .font(.caption.weight(.medium))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(severity == .info ? Color.green : severity.color)
            .background((severity == .info ? Color.green : severity.color).opacity(0.12), in: Capsule())
            .fixedSize()
    }
}

/// Small rounded tile holding an SF Symbol, used as a leading icon on cards and rows.
struct SymbolBadge: View {
    let symbol: String
    var size: CGFloat = 34
    @Environment(\.appAccent) private var accent

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: size, height: size)
            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Coloured callout with an icon, title, text and optional action, for warnings and notices.
struct NoticeBanner: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = .orange
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let actionTitle, let action { Button(actionTitle, action: action) }
        }
        .padding(14)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.3)))
        .accessibilityElement(children: .combine)
    }
}
