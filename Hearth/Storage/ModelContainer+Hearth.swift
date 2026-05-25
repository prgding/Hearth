import Foundation
import SwiftData

enum HearthStore {
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([Portfolio.self, Holding.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
