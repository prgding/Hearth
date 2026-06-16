import Foundation

enum USQuoteSource: String, CaseIterable, Identifiable, Sendable {
    case yahoo
    case sina

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .yahoo: "Yahoo Finance"
        case .sina: "新浪美股"
        }
    }
}

/// Routes a batch of `SymbolKey` to provider(s) per market with failover.
nonisolated final class QuoteRouter: Sendable {
    private let tencent: TencentQuoteProvider
    private let sina: SinaQuoteProvider
    private let yahoo: YahooQuoteProvider

    init(
        tencent: TencentQuoteProvider = TencentQuoteProvider(),
        sina: SinaQuoteProvider = SinaQuoteProvider(),
        yahoo: YahooQuoteProvider = YahooQuoteProvider()
    ) {
        self.tencent = tencent
        self.sina = sina
        self.yahoo = yahoo
    }

    func fetch(_ keys: [SymbolKey], usSource: USQuoteSource) async -> [SymbolKey: Quote] {
        guard !keys.isEmpty else { return [:] }
        let aShare = keys.filter { $0.market == .aShare }
        let us = keys.filter { $0.market == .usStock }

        async let aShareResult: [SymbolKey: Quote] = fetchAShare(aShare)
        async let usResult: [SymbolKey: Quote] = fetchUS(us, source: usSource)

        let (a, u) = await (aShareResult, usResult)
        return a.merging(u) { _, b in b }
    }

    private func fetchAShare(_ keys: [SymbolKey]) async -> [SymbolKey: Quote] {
        guard !keys.isEmpty else { return [:] }
        // Tencent first, Sina fallback.
        var result: [SymbolKey: Quote]
        if let primary = try? await tencent.fetch(keys), !primary.isEmpty {
            result = primary
            let missing = keys.filter { result[$0] == nil }
            if !missing.isEmpty, let backfill = try? await sina.fetch(missing) {
                result.merge(backfill) { a, _ in a }
            }
        } else {
            result = (try? await sina.fetch(keys)) ?? [:]
        }
        return zeroChangeBeforeOpen(result)
    }

    /// Before the A-share session opens, the feeds still serve the prior close
    /// as `last` with a stale `prevClose`, which reads as yesterday's gain. Pin
    /// `prevClose` to `last` so today's change shows 0 until trading starts;
    /// `last` (and therefore market value) is untouched.
    private func zeroChangeBeforeOpen(_ quotes: [SymbolKey: Quote]) -> [SymbolKey: Quote] {
        guard MarketSchedule.isBeforeAShareOpen() else { return quotes }
        return quotes.mapValues { q in
            Quote(key: q.key, name: q.name, last: q.last, prevClose: q.last, timestamp: q.timestamp)
        }
    }

    private func fetchUS(_ keys: [SymbolKey], source: USQuoteSource) async -> [SymbolKey: Quote] {
        guard !keys.isEmpty else { return [:] }
        let primary: QuoteProvider
        let backup: QuoteProvider
        switch source {
        case .yahoo:
            primary = yahoo; backup = sina
        case .sina:
            primary = sina; backup = yahoo
        }
        if let result = try? await primary.fetch(keys), !result.isEmpty {
            let missing = keys.filter { result[$0] == nil }
            if missing.isEmpty { return result }
            if let backfill = try? await backup.fetch(missing) {
                return result.merging(backfill) { a, _ in a }
            }
            return result
        }
        return (try? await backup.fetch(keys)) ?? [:]
    }
}
