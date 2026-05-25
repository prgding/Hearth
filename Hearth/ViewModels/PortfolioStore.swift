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

    init(context: ModelContext, router: QuoteRouter = QuoteRouter()) {
        self.context = context
        self.router = router
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

    // MARK: Quote refresh

    func refresh(usSource: USQuoteSource) async {
        let portfolios = allPortfolios()
        let allKeys = Array(Set(portfolios.flatMap { $0.holdings.map(\.key) }))
        let openKeys = allKeys.filter { MarketSchedule.isOpen($0.market) }
        guard !openKeys.isEmpty else { return }

        let fresh = await router.fetch(openKeys, usSource: usSource)
        if fresh.isEmpty {
            lastError = "行情拉取失败"
        } else {
            quotes.merge(fresh) { _, b in b }
            lastRefreshAt = .now
            lastError = nil
        }
    }

    /// One-shot fetch used by AddHoldingSheet's "测试行情" button.
    func probe(_ key: SymbolKey, usSource: USQuoteSource) async -> Quote? {
        let result = await router.fetch([key], usSource: usSource)
        return result[key]
    }

    // MARK: Aggregates for a portfolio

    func todayPnL(for portfolio: Portfolio) -> Double {
        portfolio.holdings.reduce(0) { acc, h in
            guard let q = quotes[h.key] else { return acc }
            return acc + (q.change * h.shares)
        }
    }

    func totalCost(for portfolio: Portfolio) -> Double {
        portfolio.holdings.reduce(0) { $0 + $1.costPrice * $1.shares }
    }

    func marketValue(for portfolio: Portfolio) -> Double {
        portfolio.holdings.reduce(0) { acc, h in
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
            guard let q = quotes[h.key] else { continue }
            numer += q.change * h.shares
            denom += q.prevClose * h.shares
        }
        return denom == 0 ? 0 : numer / denom
    }
}
