import Foundation

nonisolated struct SymbolKey: Hashable, Sendable, Codable {
    let market: Market
    let symbol: String
}

nonisolated enum ExtendedSession: String, Sendable, Codable {
    case pre
    case post

    var displayName: String {
        switch self {
        case .pre: "盘前"
        case .post: "盘后"
        }
    }
}

nonisolated struct Quote: Sendable, Equatable, Codable {
    let key: SymbolKey
    let name: String
    let last: Double
    let prevClose: Double
    let timestamp: Date
    /// Extended-hours session currently reflected by `extendedPrice`, if any.
    var extendedSession: ExtendedSession?
    var extendedPrice: Double?
    var extendedChange: Double?
    var extendedChangePct: Double?

    init(
        key: SymbolKey,
        name: String,
        last: Double,
        prevClose: Double,
        timestamp: Date,
        extendedSession: ExtendedSession? = nil,
        extendedPrice: Double? = nil,
        extendedChange: Double? = nil,
        extendedChangePct: Double? = nil
    ) {
        self.key = key
        self.name = name
        self.last = last
        self.prevClose = prevClose
        self.timestamp = timestamp
        self.extendedSession = extendedSession
        self.extendedPrice = extendedPrice
        self.extendedChange = extendedChange
        self.extendedChangePct = extendedChangePct
    }

    var change: Double { last - prevClose }
    var changePct: Double { prevClose == 0 ? 0 : change / prevClose }
}
