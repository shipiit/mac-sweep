import SwiftUI

/// Rounded panel used by the feature pages: solid background, hairline border.
struct Panel<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}

/// Square tinted icon badge.
struct IconBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// "Real-time protection · On" style tile under a hero.
struct InfoTile: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: String
    var valueColor: Color = .primary
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { tile }.buttonStyle(.plain)
        } else {
            tile
        }
    }

    private var tile: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout).foregroundStyle(.secondary)
                Text(value).font(.headline).foregroundStyle(valueColor).lineLimit(1)
            }
            Spacer(minLength: 4)
            if action != nil { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Card with a coloured title icon, subtitle and free content; the header can open a page.
struct FeatureCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    let subtitle: String
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                if let action {
                    Button(action: action) { header }.buttonStyle(.plain)
                } else {
                    header
                }
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                content
            }
        }
    }
}

extension FeatureCard {
    fileprivate var header: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            if action != nil { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
        }
        .contentShape(Rectangle())
    }
}

/// "XProtect · Active" row with a coloured dot and text, so state never relies on colour alone.
struct StatusRow: View {
    let symbol: String
    let title: String
    let detail: String
    let state: String
    let isGood: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary).frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Label(state, systemImage: "circle.fill").labelStyle(.titleAndIcon)
                .font(.caption.weight(.semibold)).foregroundStyle(isGood ? .green : .orange)
                .imageScale(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Timeline entry: round icon, title, detail and relative time.
struct ActivityRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let date: Date?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(tint, in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if let date { Text(Format.relative(date)).font(.caption).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .combine)
    }
}
