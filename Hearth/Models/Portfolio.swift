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

    init(name: String, shortName: String? = nil, orderIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.shortName = shortName ?? name
        self.orderIndex = orderIndex
        self.createdAt = .now
    }
}
