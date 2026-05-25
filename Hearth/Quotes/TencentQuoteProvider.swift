import Foundation

/// Tencent finance HTTP quote provider.
///
/// API: `https://qt.gtimg.cn/q=sh600519,sz000001`
/// Response (one line per stock):
/// ```
/// v_sh600519="1~贵州茅台~600519~1700.00~1690.00~1685.00~...";
/// ```
/// Tilde-separated fields, indexed from 0 after the leading "1":
///   1 = name, 2 = code, 3 = last, 4 = prev close, 30 = timestamp
nonisolated final class TencentQuoteProvider: QuoteProvider {
    let supportedMarkets: Set<Market> = [.aShare]

    func fetch(_ keys: [SymbolKey]) async throws -> [SymbolKey: Quote] {
        let aShareKeys = keys.filter { $0.market == .aShare }
        guard !aShareKeys.isEmpty else { return [:] }

        let parts = aShareKeys.map { SymbolNormalizer.tencentASharePart($0.symbol) }
        let query = parts.joined(separator: ",")
        guard let url = URL(string: "https://qt.gtimg.cn/q=\(query)") else {
            throw QuoteError.invalidResponse
        }
        let raw = try await HTTPHelper.get(url, decodeAs: HTTPHelper.gb18030)
        return parse(raw, requestedKeys: aShareKeys)
    }

    func parse(_ raw: String, requestedKeys: [SymbolKey]) -> [SymbolKey: Quote] {
        var out: [SymbolKey: Quote] = [:]
        let byCode: [String: SymbolKey] = Dictionary(
            uniqueKeysWithValues: requestedKeys.map { ($0.symbol, $0) }
        )
        for line in raw.split(whereSeparator: { $0 == "\n" || $0 == ";" }) {
            // line example: v_sh600519="1~贵州茅台~600519~1700.00~1690.00~..."
            guard let eq = line.firstIndex(of: "="),
                  let openQuote = line[eq...].firstIndex(of: "\""),
                  let closeQuote = line[line.index(after: openQuote)...].firstIndex(of: "\"") else {
                continue
            }
            let payload = line[line.index(after: openQuote)..<closeQuote]
            let fields = payload.split(separator: "~", omittingEmptySubsequences: false)
            guard fields.count > 30 else { continue }
            let name = String(fields[1])
            let code = String(fields[2])
            guard let last = Double(fields[3]), let prev = Double(fields[4]) else { continue }
            guard let key = byCode[code] else { continue }
            let ts = parseTimestamp(String(fields[30]))
            out[key] = Quote(
                key: key,
                name: name,
                last: last,
                prevClose: prev,
                timestamp: ts
            )
        }
        return out
    }

    private func parseTimestamp(_ s: String) -> Date {
        // Format: yyyyMMddHHmmss in Shanghai time
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "Asia/Shanghai")
        fmt.dateFormat = "yyyyMMddHHmmss"
        return fmt.date(from: s) ?? .now
    }
}
