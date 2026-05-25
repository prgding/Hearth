import Foundation

nonisolated struct SymbolKey: Hashable, Sendable, Codable {
    let market: Market
    let symbol: String
}

nonisolated struct Quote: Sendable, Equatable, Codable {
    let key: SymbolKey
    let name: String
    let last: Double
    let prevClose: Double
    let timestamp: Date

    var change: Double { last - prevClose }
    var changePct: Double { prevClose == 0 ? 0 : change / prevClose }
}
