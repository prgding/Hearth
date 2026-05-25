import Foundation
import SwiftData

@Model
final class Holding {
    var symbol: String
    var marketRaw: String
    var shares: Double
    var costPrice: Double
    var addedAt: Date
    var portfolio: Portfolio?

    init(symbol: String, market: Market, shares: Double, costPrice: Double) {
        self.symbol = symbol
        self.marketRaw = market.rawValue
        self.shares = shares
        self.costPrice = costPrice
        self.addedAt = .now
    }

    var market: Market {
        Market(rawValue: marketRaw) ?? .aShare
    }

    var key: SymbolKey {
        SymbolKey(market: market, symbol: symbol)
    }
}
