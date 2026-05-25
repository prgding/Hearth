import Foundation

nonisolated enum Market: String, Codable, CaseIterable, Identifiable, Sendable {
    case aShare
    case usStock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aShare: "A 股"
        case .usStock: "美股"
        }
    }

    var currencySymbol: String {
        switch self {
        case .aShare: "¥"
        case .usStock: "$"
        }
    }

    var timeZone: TimeZone {
        switch self {
        case .aShare: TimeZone(identifier: "Asia/Shanghai")!
        case .usStock: TimeZone(identifier: "America/New_York")!
        }
    }
}
