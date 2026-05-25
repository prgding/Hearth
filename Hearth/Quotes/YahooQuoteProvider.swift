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
            out[key] = Quote(key: key, name: name, last: last, prevClose: prev, timestamp: ts)
        }
        return out
    }
}
