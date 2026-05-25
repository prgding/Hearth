import Foundation

nonisolated enum MarketSchedule {
    static func isOpen(_ market: Market, at date: Date = .now) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = market.timeZone
        let weekday = cal.component(.weekday, from: date)
        // 1=Sunday, 7=Saturday
        guard weekday >= 2 && weekday <= 6 else { return false }

        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let minutes = h * 60 + m

        switch market {
        case .aShare:
            // 09:30–11:30 or 13:00–15:00, Shanghai time
            return (570...690).contains(minutes) || (780...900).contains(minutes)
        case .usStock:
            // 09:30–16:00, New York time (DST handled by Calendar)
            return (570...960).contains(minutes)
        }
    }

    static func anyOpen(_ markets: Set<Market>, at date: Date = .now) -> Bool {
        markets.contains { isOpen($0, at: date) }
    }
}
