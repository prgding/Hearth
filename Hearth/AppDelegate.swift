import AppKit
import SwiftUI
import SwiftData

/// Owns the `NSStatusItem` (so we can render a multi-line label, which
/// SwiftUI's `MenuBarExtra` cannot) and the `NSPopover` that hosts the UI.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var renderer: MenuBarRenderer!
    private var eventMonitor: Any?

    private var container: ModelContainer!
    private var store: PortfolioStore!
    private var refresher: QuoteRefresher!

    func applicationDidFinishLaunching(_ notification: Notification) {
        container = HearthStore.makeContainer()
        store = PortfolioStore(context: ModelContext(container))
        refresher = QuoteRefresher(store: store)

        let defaults = UserDefaults.standard
        let savedInterval = defaults.integer(forKey: "refreshIntervalSeconds")
        refresher.interval = TimeInterval(savedInterval > 0 ? savedInterval : 10)
        if let raw = defaults.string(forKey: "usQuoteProvider"),
           let src = USQuoteSource(rawValue: raw) {
            refresher.usSource = src
        }
        refresher.start()

        setupStatusItem()
        setupPopover()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refresher?.stop()
    }

    // MARK: Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        button.action = #selector(togglePopover(_:))
        button.target = self

        renderer = MenuBarRenderer(statusItem: statusItem, store: store)
        renderer.start()
    }

    // MARK: Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
        let root = MenuBarPopover()
            .environment(store)
            .environment(refresher)
            .modelContainer(container)
        popover.contentViewController = NSHostingController(rootView: root)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: NSPopoverDelegate

    /// `.transient` alone doesn't always close the popover in an LSUIElement
    /// app — a click in another app may not reach our window. Mirror it with
    /// a global mouse monitor that force-closes on any click anywhere (clicks
    /// on the status item itself and inside the popover are delivered to our
    /// own app, so this monitor doesn't see them and the button toggle stays
    /// intact).
    func popoverWillShow(_ notification: Notification) {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover.performClose(nil) }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
    }
}
