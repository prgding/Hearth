import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class PortfolioStore {
    var quotes: [SymbolKey: Quote] = [:]
    var lastError: String?
    var lastRefreshAt: Date?

    private let router: QuoteRouter
    private let context: ModelContext

    private static let quotesCacheKey = "cachedQuotes.v1"

    init(context: ModelContext, router: QuoteRouter = QuoteRouter()) {
        self.context = context
        self.router = router
        let cached = Self.loadCachedQuotes()
        self.quotes = cached
        // Surface the last-known fetch time so the popover footer shows when
        // the cached data was pulled (e.g. yesterday's close), not blank.
        self.lastRefreshAt = cached.values.map(\.timestamp).max()
    }

    // MARK: Portfolio lookups

    func allPortfolios() -> [Portfolio] {
        let descriptor = FetchDescriptor<Portfolio>(
            sortBy: [SortDescriptor(\Portfolio.orderIndex), SortDescriptor(\Portfolio.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func portfolio(id idString: String?) -> Portfolio? {
        guard let idString, let uuid = UUID(uuidString: idString) else { return nil }
        let descriptor = FetchDescriptor<Portfolio>(
            predicate: #Predicate { $0.id == uuid }
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// Look up a holding by its `PersistentIdentifier` in *our* context — the
    /// popover's `@Environment` context is a different `ModelContext` instance
    /// and won't have it cached.
    func holding(id: PersistentIdentifier) -> Holding? {
        context.registeredModel(for: id)
    }

    // MARK: Mutations

    /// All deletes/saves must run on the store's own context. The popover's
    /// `@Environment(\.modelContext)` is a *different* context, so calling
    /// `delete()` there on an object fetched here is a no-op (the object isn't
    /// registered in that context). Route every mutation through the store.
    func delete(_ holding: Holding) {
        context.delete(holding)
        try? context.save()
    }

    func delete(_ portfolio: Portfolio) {
        context.delete(portfolio)
        try? context.save()
    }

    func insert(_ portfolio: Portfolio) {
        context.insert(portfolio)
        try? context.save()
    }

    func add(_ holding: Holding, to portfolio: Portfolio) {
        holding.portfolio = portfolio
        context.insert(holding)
        try? context.save()
    }

    func save() {
        try? context.save()
    }

    // MARK: Quote refresh

    /// Fetch fresh quotes for every holding and report whether any held market
    /// is currently in its fast-polling window — the refresher uses that to pick
    /// the fast vs. 30s idle cadence.
    ///
    /// We fetch *all* holdings unconditionally rather than narrowing to the
    /// active markets: narrowing froze a held-but-closed market for the whole of
    /// another market's session and left a newly-added closed-market holding
    /// with no quote until its market opened. Portfolios are personal-scale, so
    /// the extra requests are cheap.
    @discardableResult
    func refresh(usSource: USQuoteSource) async -> Bool {
        let keys = Array(Set(allPortfolios().flatMap { $0.holdings.map(\.key) }))
        guard !keys.isEmpty else { return false }
        let anyActive = Set(keys.map(\.market)).contains { MarketSchedule.shouldPoll($0) }

        let fresh = await router.fetch(keys, usSource: usSource)
        if fresh.isEmpty {
            lastError = "行情拉取失败"
        } else {
            quotes.merge(fresh) { _, b in b }
            lastRefreshAt = .now
            lastError = nil
            Self.saveCachedQuotes(quotes)
        }
        return anyActive
    }

    // MARK: Quote cache (across launches)

    private static func loadCachedQuotes() -> [SymbolKey: Quote] {
        guard let data = UserDefaults.standard.data(forKey: quotesCacheKey),
              let list = try? JSONDecoder().decode([Quote].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.key, $0) })
    }

    private static func saveCachedQuotes(_ quotes: [SymbolKey: Quote]) {
        guard let data = try? JSONEncoder().encode(Array(quotes.values)) else { return }
        UserDefaults.standard.set(data, forKey: quotesCacheKey)
    }

    /// One-shot fetch used by AddHoldingSheet's "测试行情" button.
    func probe(_ key: SymbolKey, usSource: USQuoteSource) async -> Quote? {
        let result = await router.fetch([key], usSource: usSource)
        return result[key]
    }

    // MARK: Aggregates for a portfolio

    func todayPnL(for portfolio: Portfolio) -> Double {
        portfolio.holdings.reduce(0) { acc, h in
            guard h.includedInTotal, let q = quotes[h.key] else { return acc }
            return acc + (q.change * h.shares)
        }
    }

    func totalCost(for portfolio: Portfolio) -> Double {
        portfolio.holdings.reduce(0) { acc, h in
            guard h.includedInTotal else { return acc }
            return acc + h.costPrice * h.shares
        }
    }

    func marketValue(for portfolio: Portfolio) -> Double {
        portfolio.holdings.reduce(0) { acc, h in
            guard h.includedInTotal else { return acc }
            let price = quotes[h.key]?.last ?? h.costPrice
            return acc + price * h.shares
        }
    }

    func totalPnL(for portfolio: Portfolio) -> Double {
        marketValue(for: portfolio) - totalCost(for: portfolio)
    }

    /// Cost-weighted today's percentage change for the portfolio.
    /// (sum of change_i * shares_i) / (sum of prevClose_i * shares_i)
    func todayPnLPercent(for portfolio: Portfolio) -> Double {
        var numer = 0.0
        var denom = 0.0
        for h in portfolio.holdings {
            guard h.includedInTotal, let q = quotes[h.key] else { continue }
            numer += q.change * h.shares
            denom += q.prevClose * h.shares
        }
        return denom == 0 ? 0 : numer / denom
    }
}
