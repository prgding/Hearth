import AppKit

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
    private var storeObserver: NSObjectProtocol?
    private var renderScheduled = false
    private var lastPinnedSlot1Id: String?
    private var lastPinnedSlot2Id: String?
    private var lastImageWidth: CGFloat?

    init(statusItem: NSStatusItem, store: PortfolioStore) {
        self.statusItem = statusItem
        self.store = store
    }

    deinit {
        if let o = settingsObserver { NotificationCenter.default.removeObserver(o) }
        if let o = storeObserver { NotificationCenter.default.removeObserver(o) }
    }

    func start() {
        storeObserver = NotificationCenter.default.addObserver(
            forName: PortfolioStore.displayDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRender() }
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderIfPinnedSelectionChanged() }
        }
        render()
    }

    /// Coalesce a burst of store mutations into at most one render per main
    /// run-loop turn. Do not use `withObservationTracking` here: reading a
    /// SwiftData relationship while rendering can itself invalidate the
    /// observation access list. Re-subscribing from `onChange` then forms a
    /// self-sustaining render loop that eventually pins the main thread.
    private func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.renderScheduled = false
            self.render()
        }
    }

    /// The quote cache also lives in UserDefaults and changes after every
    /// refresh. Only the two pinned IDs affect the status item, so ignore all
    /// unrelated defaults notifications.
    private func renderIfPinnedSelectionChanged() {
        let slot1 = UserDefaults.standard.string(forKey: "pinnedSlot1Id") ?? ""
        let slot2 = UserDefaults.standard.string(forKey: "pinnedSlot2Id") ?? ""
        guard slot1 != lastPinnedSlot1Id || slot2 != lastPinnedSlot2Id else { return }
        scheduleRender()
    }

    private func render() {
        let slot1 = UserDefaults.standard.string(forKey: "pinnedSlot1Id") ?? ""
        let slot2 = UserDefaults.standard.string(forKey: "pinnedSlot2Id") ?? ""
        lastPinnedSlot1Id = slot1
        lastPinnedSlot2Id = slot2

        let p1 = pinnedPortfolio(id: slot1)
        let p2 = pinnedPortfolio(id: slot2)
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
            // image; reproducible on every cold start. Park at
            // variableLength for one runloop tick to force all mirrored
            // buttons to recompute their layout — but keep the new image
            // set the whole time: nil-ing it here made the item visibly
            // vanish for a frame whenever the PnL string changed digit
            // count (the "menubar flicker").
            button.image = img
            statusItem.length = NSStatusItem.variableLength
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
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
        let pnl = store.todayPnLInCNY(for: p)
        return PnLFormatter.amountString(pnl)
    }

    private static func renderTwoLineTemplate(line1: String, line2: String) -> NSImage {
        // Use monospaced *digits* on the regular system font, not the full
        // SF Mono face — SF Mono has no CJK glyphs, so the "未选" placeholder
        // forces CoreText into font fallback. That fallback occasionally
        // returns a nil substituted font, crashing -[NSAttributedString size]
        // in TAttributes::ApplyFont. The digit-only variant keeps two-line
        // PnL alignment while letting the system font render CJK natively.
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
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
        // Right-align both lines: each line's right edge sits at `width - hPad`,
        // so a shorter line is pushed right to line up its trailing digit.
        s1.draw(at: NSPoint(x: width - hPad - sz1.width, y: sz2.height))
        s2.draw(at: NSPoint(x: width - hPad - sz2.width, y: 0))
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    private func pinnedPortfolio(id: String) -> Portfolio? {
        return store.portfolio(id: id.isEmpty ? nil : id)
    }
}
