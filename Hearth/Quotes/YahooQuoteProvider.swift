import Foundation

/// Yahoo Finance public quote endpoint.
///
/// `https://query1.finance.yahoo.com/v7/finance/quote?symbols=AAPL,MSFT`
nonisolated final class YahooQuoteProvider: QuoteProvider {
    let supportedMarkets: Set<Market> = [.usStock]

    private struct Envelope: Decodable {
        let quoteResponse: QuoteResponse
        struct QuoteResponse: Decodable {
            let result: [Item]
        }
        struct Item: Decodable {
            let symbol: String
            let shortName: String?
            let longName: String?
            let regularMarketPrice: Double?
            let regularMarketPreviousClose: Double?
            let regularMarketTime: Int?
            let marketState: String?
            let preMarketPrice: Double?
            let preMarketChange: Double?
            let preMarketChangePercent: Double?
            let postMarketPrice: Double?
            let postMarketChange: Double?
            let postMarketChangePercent: Double?
        }
    }

    func fetch(_ keys: [SymbolKey]) async throws -> [SymbolKey: Quote] {
        let usKeys = keys.filter { $0.market == .usStock }
        guard !usKeys.isEmpty else { return [:] }

        let symbols = usKeys.map(\.symbol).joined(separator: ",")
        var comps = URLComponents(string: "https://query1.finance.yahoo.com/v7/finance/quote")!
        comps.queryItems = [URLQueryItem(name: "symbols", value: symbols)]
        guard let url = comps.url else { throw QuoteError.invalidResponse }

        let data = try await HTTPHelper.getJSON(url)
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)

        let bySymbol: [String: SymbolKey] = Dictionary(
            uniqueKeysWithValues: usKeys.map { ($0.symbol, $0) }
        )
        var out: [SymbolKey: Quote] = [:]
        for item in envelope.quoteResponse.result {
            guard let key = bySymbol[item.symbol] else { continue }
            guard let last = item.regularMarketPrice, let prev = item.regularMarketPreviousClose else { continue }
            let name = item.shortName ?? item.longName ?? item.symbol
            let ts = item.regularMarketTime.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .now

            // Yahoo's marketState transitions: PREPRE → PRE → REGULAR → POST → POSTPOST → CLOSED.
            // Show pre-market only while it's actively the current session; show post-market
            // any time post-data is fresher than the regular close (i.e. after 16:00 ET).
            let state = item.marketState ?? ""
            var session: ExtendedSession?
            var extPrice: Double?
            var extChg: Double?
            var extPct: Double?
            if state == "PRE" || state == "PREPRE", let p = item.preMarketPrice {
                session = .pre
                extPrice = p
                extChg = item.preMarketChange
                extPct = item.preMarketChangePercent.map { $0 / 100 }
            } else if let p = item.postMarketPrice,
                      ["POST", "POSTPOST", "CLOSED"].contains(state) {
                session = .post
                extPrice = p
                extChg = item.postMarketChange
                extPct = item.postMarketChangePercent.map { $0 / 100 }
            }

            // When extended-hours data is available, treat the extended print as the
            // current price so `q.change` reflects the full cumulative move from
            // yesterday's close. The session-specific delta is preserved in
            // `extendedChange`/`extendedChangePct` for the subtitle line.
            let displayPrice = extPrice ?? last
            out[key] = Quote(
                key: key,
                name: name,
                last: displayPrice,
                prevClose: prev,
                timestamp: ts,
                extendedSession: session,
                extendedPrice: extPrice,
                extendedChange: extChg,
                extendedChangePct: extPct
            )
        }
        return out
    }
}
