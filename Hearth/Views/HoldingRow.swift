import SwiftUI

struct HoldingRow: View {
    let holding: Holding
    let quote: Quote?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(quote?.name ?? holding.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(holding.symbol)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("\(formatShares(holding.shares)) 股 · 成本 \(format(holding.costPrice))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatPnL(todayPnL))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                if let q = quote {
                    Text(PnLFormatter.percentString(q.changePct))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
            VStack(alignment: .trailing, spacing: 2) {
                if let q = quote {
                    Text(formatValue(q.last * holding.shares))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text("浮盈 \(formatPnL(totalPnL))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.primary)
                    if let session = q.extendedSession {
                        Text(session.displayName)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 90, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private var todayPnL: Double {
        guard let q = quote else { return 0 }
        return q.change * holding.shares
    }

    private var totalPnL: Double {
        let price = quote?.last ?? holding.costPrice
        return (price - holding.costPrice) * holding.shares
    }

    private func format(_ v: Double) -> String {
        String(format: "%.2f", v)
    }

    private static let valueFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = true
        return f
    }()

    /// Real-time market value (price × shares), grouped for readability.
    private func formatValue(_ v: Double) -> String {
        Self.valueFormatter.string(from: NSNumber(value: v)) ?? format(v)
    }

    private func formatShares(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", v)
        }
        return String(format: "%.2f", v)
    }

    private func formatPnL(_ v: Double) -> String {
        let prefix = v > 0 ? "+" : ""
        return "\(prefix)\(format(v))"
    }
}
