import Foundation

nonisolated enum MarketSchedule {
    /// Whether the quote loop should poll `market` at its *fast* cadence right
    /// now — the market is in (or adjacent to) an active session. Outside these
    /// windows the refresher falls back to a slow idle tick instead of freezing.
    ///
    /// - A-share: 09:15 opening call auction → 11:30, then 13:00–15:00 (the
    ///   13:00–15:00 leg also covers the 14:57–15:00 closing auction). The
    ///   11:30–13:00 lunch break is left to the idle tier.
    /// - US: 04:00–20:00 ET — pre + regular + after-hours.
    static func shouldPoll(_ market: Market, at date: Date = .now) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = market.timeZone
        let weekday = cal.component(.weekday, from: date)
        guard weekday >= 2 && weekday <= 6 else { return false }

        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let minutes = h * 60 + m

        switch market {
        case .aShare:
            // 09:15 (555) → 11:30 (690), and 13:00 (780) → 15:00 (900).
            return (555...690).contains(minutes) || (780...900).contains(minutes)
        case .usStock:
            // 04:00 (240) → 20:00 (1200) ET.
            return (240...1200).contains(minutes)
        }
    }

    /// True from midnight up to the A-share opening call auction (00:00–09:15
    /// Shanghai). In this window the upstream feeds still report the *previous*
    /// session's close as `last` while `prevClose` hasn't rolled over yet, so the
    /// implied change is yesterday's move rather than today's. Callers zero
    /// today's change here. A-share only — US 04:00 ET is a genuine pre-market
    /// session we do want to surface.
    static func isBeforeAShareOpen(at date: Date = .now) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Market.aShare.timeZone
        let minutes = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        return minutes < 555  // before 09:15
    }
}
