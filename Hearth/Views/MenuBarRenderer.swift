import AppKit
import Observation

/// Drives the `NSStatusItem` button content. Renders the pinned portfolios'
/// PnL into a template `NSImage` — `isTemplate = true` lets AppKit tint and
/// dim it the same way it does the native menu extras (clock, battery), so
/// an inactive menubar fades automatically.
@MainActor
final class MenuBarRenderer {
    private let statusItem: NSStatusItem
    private let store: PortfolioStore

    private var button: NSStatusBarButton { statusItem.button! }
    private var settingsObserver: NSObjectProtocol?
    private var lastImageWidth: CGFloat?

    init(statusItem: NSStatusItem, store: PortfolioStore) {
        self.statusItem = statusItem
        self.store = store
    }

    deinit {
        if let o = settingsObserver { NotificationCenter.default.removeObserver(o) }
    }

    func start() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRender() }
        }
        scheduleRender()
    }

    private func scheduleRender() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.scheduleRender() }
        }
    }

    private func render() {
        let p1 = pinnedPortfolio(key: "pinnedSlot1Id")
        let p2 = pinnedPortfolio(key: "pinnedSlot2Id")
        let img = templateImage(p1: p1, p2: p2)
        let newWidth = img?.size.width ?? 0
        let pinned = newWidth + 4

        if lastImageWidth == newWidth {
            // Same width as the last render — no relayout needed.
            button.image = img
            statusItem.length = pinned
        } else {
            // First render after launch or a width change. Secondary
            // (non-key) displays mirror the status item but cache the
            // prior button width and clip the new (typically narrower)
            // image; reproducible on every cold start. Park in a neutral
            // state for one runloop tick to force all mirrored buttons
            // to recompute their layout.
            button.image = nil
            statusItem.length = NSStatusItem.variableLength
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.button.image = img
                self.statusItem.length = pinned
            }
        }
        lastImageWidth = newWidth
    }

    // MARK: Template image rendering

    private func templateImage(p1: Portfolio?, p2: Portfolio?) -> NSImage? {
        if p1 == nil && p2 == nil {
            let img = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: nil)
            img?.isTemplate = true
            return img
        }
        return Self.renderTwoLineTemplate(
            line1: labelString(for: p1),
            line2: labelString(for: p2)
        )
    }

    private func labelString(for portfolio: Portfolio?) -> String {
        guard let p = portfolio else { return "未选" }
        let pnl = store.todayPnL(for: p)
        return PnLFormatter.amountString(pnl)
    }

    private static func renderTwoLineTemplate(line1: String, line2: String) -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        // Color is ignored when `isTemplate = true`; AppKit tints by the menubar
        // appearance and applies the inactive dim itself.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let s1 = NSAttributedString(string: line1, attributes: attrs)
        let s2 = NSAttributedString(string: line2, attributes: attrs)
        let sz1 = s1.size()
        let sz2 = s2.size()
        // Horizontal padding so the last glyph isn't clipped by antialiasing
        // bleed past the calculated string bounds.
        let hPad: CGFloat = 4
        let width = ceil(max(sz1.width, sz2.width)) + hPad * 2
        let height = ceil(sz1.height + sz2.height)
        // Rasterize immediately with lockFocus rather than the lazy
        // `drawingHandler:` initializer — the lazy form was observed to draw
        // only a clipped subregion when AppKit re-rasterized for a non-key
        // secondary display.
        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()
        s1.draw(at: NSPoint(x: hPad, y: sz2.height))
        s2.draw(at: NSPoint(x: hPad, y: 0))
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    private func pinnedPortfolio(key: String) -> Portfolio? {
        let id = UserDefaults.standard.string(forKey: key) ?? ""
        return store.portfolio(id: id.isEmpty ? nil : id)
    }
}
