import Foundation

nonisolated enum SymbolNormalizer {
    /// Returns the canonical lookup key as stored on `Holding.symbol`:
    /// - A-share: 6-digit numeric, no prefix (e.g. "600519")
    /// - US: uppercase letters (e.g. "AAPL")
    static func canonical(_ raw: String, market: Market) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch market {
        case .aShare:
            let digits = trimmed.filter(\.isNumber)
            return String(digits.suffix(6))
        case .usStock:
            return trimmed.uppercased()
        }
    }

    /// A-share market code prefix used by Sina/Tencent: sh / sz / bj
    static func aShareExchangePrefix(_ canonical: String) -> String {
        guard let first = canonical.first else { return "sh" }
        switch first {
        case "6", "9":  return "sh"   // 沪市 + B股
        case "0", "3":  return "sz"   // 深市
        case "4", "8":  return "bj"   // 北交所 / 三板
        default:        return "sh"
        }
    }

    /// e.g. "sh600519" for Tencent's `q=` param
    static func tencentASharePart(_ canonical: String) -> String {
        aShareExchangePrefix(canonical) + canonical
    }

    /// Sina uses the same prefix for A-share and `gb_` for US.
    static func sinaPart(_ key: SymbolKey) -> String {
        switch key.market {
        case .aShare: aShareExchangePrefix(key.symbol) + key.symbol
        case .usStock: "gb_" + key.symbol.lowercased()
        }
    }
}
