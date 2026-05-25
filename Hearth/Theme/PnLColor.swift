import SwiftUI

enum PnLColor {
    static func of(_ change: Double) -> Color {
        if change > 0 { .red }
        else if change < 0 { .green }
        else { .secondary }
    }
}

enum PnLFormatter {
    static let amount: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        f.positivePrefix = "+"
        f.negativePrefix = "-"
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()

    static let percent: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        f.positivePrefix = "+"
        f.negativePrefix = "-"
        return f
    }()

    static func amountString(_ v: Double) -> String {
        amount.string(from: NSNumber(value: v)) ?? "0.00"
    }

    static func percentString(_ v: Double) -> String {
        percent.string(from: NSNumber(value: v)) ?? "0.00%"
    }
}
