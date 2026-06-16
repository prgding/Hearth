import Foundation
import Observation

@MainActor
@Observable
final class QuoteRefresher {
    var interval: TimeInterval = 10
    var usSource: USQuoteSource = .yahoo
    /// Cadence when no held market is in its active window — slow but not frozen.
    private let idleInterval: TimeInterval = 30
    private weak var store: PortfolioStore?
    private var task: Task<Void, Never>?

    init(store: PortfolioStore) {
        self.store = store
    }

    func start() {
        stop()
        task = Task { [weak self] in
            while !Task.isCancelled {
                let active = await self?.tick() ?? false
                guard let self else { return }
                // Fast cadence while a market is active; slow (but not frozen)
                // 30s idle tick otherwise. Never idle faster than the fast rate.
                let sleep = active ? self.interval : max(self.interval, self.idleInterval)
                try? await Task.sleep(nanoseconds: UInt64(sleep * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Manual refresh — fetches all holdings immediately.
    func refreshNow() {
        Task { [weak self] in
            await self?.tick()
        }
    }

    /// Returns whether any held market is currently in its fast window.
    @discardableResult
    private func tick() async -> Bool {
        guard let store else { return false }
        return await store.refresh(usSource: usSource)
    }
}
