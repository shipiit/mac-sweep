import MacSweepCore
import SwiftUI

extension StorageCategory {
    var color: Color {
        switch self {
        case .media: .orange
        case .code: .indigo
        case .devTools: .gray
        case .sdks: .teal
        case .ai: .pink
        case .caches: .blue
        case .system: .brown
        case .other: Color(nsColor: .systemGray)
        }
    }
}

extension CleanupSafety {
    var color: Color {
        switch self {
        case .safe: .green
        case .review: .orange
        }
    }

    var title: String {
        switch self {
        case .safe: "Safe to remove"
        case .review: "Review first"
        }
    }
}

extension MemoryPressure {
    var color: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}
