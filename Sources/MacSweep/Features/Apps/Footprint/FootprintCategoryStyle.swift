import MacSweepCore
import SwiftUI

extension FootprintCategory {
    var color: Color {
        switch self {
        case .bundle: .blue
        case .caches: .orange
        case .applicationSupport: .purple
        case .containers: .teal
        case .preferences: .pink
        case .logs: .gray
        case .savedState: .brown
        case .webKit: .indigo
        }
    }

    var symbol: String {
        switch self {
        case .bundle: "app"
        case .caches: "archivebox"
        case .applicationSupport: "folder"
        case .containers: "shippingbox"
        case .preferences: "gearshape"
        case .logs: "doc.text"
        case .savedState: "macwindow"
        case .webKit: "globe"
        }
    }
}

extension AppFootprint {
    /// Segments for the shared `StackedBar`; labels and sizes keep the bar readable without colour.
    var segments: [BarSegment] {
        breakdown.map { BarSegment(label: $0.category.title, value: Double($0.size), color: $0.category.color, detail: Format.bytes($0.size)) }
    }
}
