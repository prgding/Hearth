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
            while !Task.isCancelled {
                await self?.tick()
                guard let interval = self?.interval else { return }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func tick() async {
        guard let store else { return }
        await store.refresh(usSource: usSource)
    }
}
