import Foundation
import SwiftData

@Model
final class Portfolio {
    @Attribute(.unique) var id: UUID
    var name: String
    var shortName: String
    var orderIndex: Int
    @Relationship(deleteRule: .cascade, inverse: \Holding.portfolio)
    var holdings: [Holding] = []
    var createdAt: Date
    /// Realized P&L from positions sold *today*. The broker books these into
    /// today's P&L, but Hearth no longer holds them, so we carry the figure as
    /// an offset added to today's P&L. Only applied while `todaySoldOn` is the
    /// current day (Shanghai) — it auto-expires when the day rolls over.
    var todaySoldPnL: Double = 0
    var todaySoldOn: Date? = nil

    init(name: String, shortName: String? = nil, orderIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.shortName = shortName ?? name
        self.orderIndex = orderIndex
        self.createdAt = .now
    }
}
