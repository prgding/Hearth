import Foundation

/// Sina finance HTTP quote provider — supports both A-share and US.
///
/// A-share API: `https://hq.sinajs.cn/list=sh600519,sz000001`
/// Response: `var hq_str_sh600519="贵州茅台,1685.00,1690.00,1700.00,...";`
/// Fields (0-indexed within the quoted payload, A-share format):
///   0=name, 1=today open, 2=prev close, 3=last, 30=date, 31=time
///
/// US API: `https://hq.sinajs.cn/list=gb_aapl`
/// Response: `var hq_str_gb_aapl="Apple Inc.,190.50,...";`
/// Fields (US format):
///   0=name, 1=last, 2=changePct, 26=prev close
///
/// Must send `Referer: https://finance.sina.com.cn`, else server returns empty.
nonisolated final class SinaQuoteProvider: QuoteProvider {
    let supportedMarkets: Set<Market> = [.aShare, .usStock]

    func fetch(_ keys: [SymbolKey]) async throws -> [SymbolKey: Quote] {
        guard !keys.isEmpty else { return [:] }
        let parts = keys.map { SymbolNormalizer.sinaPart($0) }
        let query = parts.joined(separator: ",")
        guard let url = URL(string: "https://hq.sinajs.cn/list=\(query)") else {
            throw QuoteError.invalidResponse
        }
        let raw = try await HTTPHelper.get(
            url,
            referer: "https://finance.sina.com.cn",
            decodeAs: HTTPHelper.gb18030
        )
        return parse(raw, requestedKeys: keys)
    }

    func parse(_ raw: String, requestedKeys: [SymbolKey]) -> [SymbolKey: Quote] {
        var out: [SymbolKey: Quote] = [:]
        var partToKey: [String: SymbolKey] = [:]
        for k in requestedKeys {
            partToKey[SymbolNormalizer.sinaPart(k)] = k
        }
        for line in raw.split(whereSeparator: { $0 == "\n" || $0 == ";" }) {
            // line: var hq_str_sh600519="..." or var hq_str_gb_aapl="..."
            guard let prefixEnd = line.range(of: "hq_str_") else { continue }
            let afterPrefix = line[prefixEnd.upperBound...]
            guard let eq = afterPrefix.firstIndex(of: "=") else { continue }
            let part = String(afterPrefix[..<eq]).trimmingCharacters(in: .whitespaces)
            guard let key = partToKey[part] else { continue }
            guard let openQuote = afterPrefix[eq...].firstIndex(of: "\""),
                  let closeQuote = afterPrefix[afterPrefix.index(after: openQuote)...].firstIndex(of: "\"") else {
                continue
            }
            let payload = afterPrefix[afterPrefix.index(after: openQuote)..<closeQuote]
            let fields = payload.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            if let q = parseQuote(fields: fields, key: key) {
                out[key] = q
            }
        }
        return out
    }

    private func parseQuote(fields: [String], key: SymbolKey) -> Quote? {
        switch key.market {
        case .aShare:
            guard fields.count >= 32 else { return nil }
            let name = fields[0]
            guard let prev = Double(fields[2]), let last = Double(fields[3]) else { return nil }
            // Sina returns last=0 before market opens; fall back to prevClose
            let realLast = last == 0 ? prev : last
            let ts = parseAShareTime(date: fields[30], time: fields[31])
            return Quote(key: key, name: name, last: realLast, prevClose: prev, timestamp: ts)
        case .usStock:
            guard fields.count >= 27 else { return nil }
            let name = fields[0]
            guard let last = Double(fields[1]), let prev = Double(fields[26]) else { return nil }
            return Quote(key: key, name: name, last: last, prevClose: prev, timestamp: .now)
        }
    }

    private func parseAShareTime(date: String, time: String) -> Date {
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "Asia/Shanghai")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fmt.date(from: "\(date) \(time)") ?? .now
    }
}
