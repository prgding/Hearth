import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class PortfolioStore {
    nonisolated static let displayDidChangeNotification = Notification.Name(
        "me.ding.Hearth.portfolioStoreDisplayDidChange"
    )

    var quotes: [SymbolKey: Quote] = [:]
    private(set) var portfolios: [Portfolio] = []
    private(set) var usdCNYRate: Double?
    var lastError: String?
    var lastRefreshAt: Date?

    private let router: QuoteRouter
    private let context: ModelContext

    private nonisolated static let quotesCacheKey = "cachedQuotes.v1"
    private nonisolated static let usdCNYRateCacheKey = "cachedUSDCNYRate.v1"
    private nonisolated static let usdCNYRateDateCacheKey = "cachedUSDCNYRateDate.v1"
    private nonisolated static let usdCNYRefreshInterval: TimeInterval = 60 * 60
    private nonisolated static let usdCNYFallbackRate = 7.0
    private var usdCNYRateDate: Date?
    private var usdCNYLastAttemptAt: Date?

    init(context: ModelContext, router: QuoteRouter = QuoteRouter()) {
        self.context = context
        self.router = router
        let cached = Self.loadCachedQuotes()
        self.quotes = cached
        let cachedRate = Self.loadCachedUSDCNYRate()
        self.usdCNYRate = cachedRate?.rate
        self.usdCNYRateDate = cachedRate?.date
        // Surface the last-known fetch time so the popover footer shows when
        // the cached data was pulled (e.g. yesterday's close), not blank.
        self.lastRefreshAt = cached.values.map(\.timestamp).max()
        reloadPortfolios()
    }

    // MARK: Portfolio lookups

    func allPortfolios() -> [Portfolio] {
        portfolios
    }

    private func reloadPortfolios() {
        let descriptor = FetchDescriptor<Portfolio>(
            sortBy: [SortDescriptor(\Portfolio.orderIndex), SortDescriptor(\Portfolio.createdAt)]
        )
        portfolios = (try? context.fetch(descriptor)) ?? []
        notifyDisplayDidChange()
    }

    private func notifyDisplayDidChange() {
        NotificationCenter.default.post(
            name: Self.displayDidChangeNotification,
            object: self
        )
    }

    func portfolio(id idString: String?) -> Portfolio? {
        guard let idString, let uuid = UUID(uuidString: idString) else { return nil }
        return portfolios.first { $0.id == uuid }
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
        reloadPortfolios()
    }

    func delete(_ portfolio: Portfolio) {
        context.delete(portfolio)
        try? context.save()
        reloadPortfolios()
    }

    func insert(_ portfolio: Portfolio) {
        context.insert(portfolio)
        try? context.save()
        reloadPortfolios()
    }

    func add(_ holding: Holding, to portfolio: Portfolio) {
        holding.portfolio = portfolio
        context.insert(holding)
        try? context.save()
        reloadPortfolios()
    }

    func save() {
        try? context.save()
        reloadPortfolios()
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
        let hasUSStocks = keys.contains { $0.market == .usStock }
        let shouldRefreshRate = hasUSStocks && shouldRefreshUSDCNYRate()

        async let freshRequest = router.fetch(keys, usSource: usSource)
        async let rateRequest: Double? = shouldRefreshRate ? router.fetchUSDCNYRate() : nil
        if shouldRefreshRate {
            usdCNYLastAttemptAt = .now
        }
        let (fresh, fetchedRate) = await (freshRequest, rateRequest)
        var displayDidChange = false

        if let fetchedRate {
            let fetchedAt = Date.now
            usdCNYRate = fetchedRate
            usdCNYRateDate = fetchedAt
            displayDidChange = true
            Self.saveCachedUSDCNYRate(fetchedRate, date: fetchedAt)
        }
        if fresh.isEmpty {
            lastError = "行情拉取失败"
        } else {
            quotes.merge(fresh) { _, b in b }
            lastRefreshAt = .now
            lastError = nil
            displayDidChange = true
            let snapshot = quotes
            Task.detached(priority: .utility) {
                Self.saveCachedQuotes(snapshot)
            }
        }
        if displayDidChange {
            notifyDisplayDidChange()
        }
        return anyActive
    }

    // MARK: Quote cache (across launches)

    private nonisolated static func loadCachedQuotes() -> [SymbolKey: Quote] {
        guard let data = UserDefaults.standard.data(forKey: quotesCacheKey),
              let list = try? JSONDecoder().decode([Quote].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.key, $0) })
    }

    private nonisolated static func saveCachedQuotes(_ quotes: [SymbolKey: Quote]) {
        guard let data = try? JSONEncoder().encode(Array(quotes.values)) else { return }
        UserDefaults.standard.set(data, forKey: quotesCacheKey)
    }

    private func shouldRefreshUSDCNYRate(now: Date = .now) -> Bool {
        let reference = usdCNYLastAttemptAt ?? usdCNYRateDate
        guard let reference else { return true }
        return now.timeIntervalSince(reference) >= Self.usdCNYRefreshInterval
    }

    private nonisolated static func loadCachedUSDCNYRate() -> (rate: Double, date: Date)? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: usdCNYRateCacheKey) != nil,
              let date = defaults.object(forKey: usdCNYRateDateCacheKey) as? Date
        else { return nil }
        let rate = defaults.double(forKey: usdCNYRateCacheKey)
        guard rate.isFinite, rate > 0 else { return nil }
        return (rate, date)
    }

    private nonisolated static func saveCachedUSDCNYRate(_ rate: Double, date: Date) {
        let defaults = UserDefaults.standard
        defaults.set(rate, forKey: usdCNYRateCacheKey)
        defaults.set(date, forKey: usdCNYRateDateCacheKey)
    }

    /// One-shot fetch used by AddHoldingSheet's "测试行情" button.
    func probe(_ key: SymbolKey, usSource: USQuoteSource) async -> Quote? {
        let result = await router.fetch([key], usSource: usSource)
        return result[key]
    }

    // MARK: Aggregates for a portfolio

    func todayPnL(for portfolio: Portfolio) -> Double {
        let held = portfolio.holdings.reduce(0.0) { acc, h in
            guard h.includedInTotal, let q = quotes[h.key] else { return acc }
            return acc + (q.change * h.shares)
        }
        return held + soldPnLToday(for: portfolio)
    }

    /// Today's P&L converted to CNY for the compact menubar display only.
    /// The popover intentionally continues to use `todayPnL(for:)` so each
    /// market remains in its native currency there. The manual sold offset has
    /// no market metadata, so it remains a CNY amount.
    func todayPnLInCNY(for portfolio: Portfolio) -> Double {
        let held = portfolio.holdings.reduce(0.0) { acc, holding in
            guard holding.includedInTotal, let quote = quotes[holding.key] else { return acc }
            let nativePnL = quote.change * holding.shares
            switch holding.market {
            case .aShare:
                return acc + nativePnL
            case .usStock:
                // Used only before the first successful network response on a
                // clean install. Subsequent launches use the cached live rate.
                return acc + nativePnL * (usdCNYRate ?? Self.usdCNYFallbackRate)
            }
        }
        return held + soldPnLToday(for: portfolio)
    }

    /// Realized P&L from positions the user sold *today*. The broker counts it
    /// in today's P&L but Hearth no longer holds those positions, so it's
    /// carried as a manual per-portfolio offset. Applied only while the stored
    /// date is the current Shanghai day, so it auto-zeroes after the rollover.
    private func soldPnLToday(for portfolio: Portfolio) -> Double {
        guard portfolio.todaySoldPnL != 0, let on = portfolio.todaySoldOn else { return 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return cal.isDate(on, inSameDayAs: .now) ? portfolio.todaySoldPnL : 0
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
