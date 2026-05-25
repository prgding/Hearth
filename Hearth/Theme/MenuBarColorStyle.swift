import Foundation

enum MenuBarColorStyle: String, CaseIterable, Identifiable, Sendable {
    case pnl
    case system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pnl: "涨跌色"
        case .system: "跟随系统"
        }
    }
}
