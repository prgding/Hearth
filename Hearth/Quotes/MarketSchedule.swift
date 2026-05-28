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

    /// Whether the quote loop should poll right now. Mirrors `isOpen` for A-share
    /// but expands to US extended hours (04:00–20:00 ET) so pre/after-market
    /// prints are picked up.
    static func shouldPoll(_ market: Market, at date: Date = .now) -> Bool {
        if market == .aShare { return isOpen(market, at: date) }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = market.timeZone
        let weekday = cal.component(.weekday, from: date)
        guard weekday >= 2 && weekday <= 6 else { return false }

        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let minutes = h * 60 + m
        // 04:00–20:00 ET covers pre + regular + after-hours sessions.
        return (240...1200).contains(minutes)
    }

    static func anyOpen(_ markets: Set<Market>, at date: Date = .now) -> Bool {
        markets.contains { isOpen($0, at: date) }
    }
}
