import Foundation
import Observation

@MainActor
@Observable
final class QuoteRefresher {
    var interval: TimeInterval = 10
    var usSource: USQuoteSource = .yahoo
    private weak var store: PortfolioStore?
    private var task: Task<Void, Never>?

    init(store: PortfolioStore) {
        self.store = store
    }

    func start() {
        stop()
        task = Task { [weak self] in
            // First tick is forced (ignores market-hours filter) so after-close
            // launches still pull the day's final prices.
            var force = true
            while !Task.isCancelled {
                await self?.tick(force: force)
                force = false
                guard let interval = self?.interval else { return }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Manual refresh — always forced so it pulls even outside market hours.
    func refreshNow() {
        Task { [weak self] in
            await self?.tick(force: true)
        }
    }

    private func tick(force: Bool) async {
        guard let store else { return }
        await store.refresh(usSource: usSource, force: force)
    }
}
