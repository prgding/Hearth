import AppKit
import SwiftUI
import SwiftData

/// Owns the `NSStatusItem` (so we can render a multi-line label, which
/// SwiftUI's `MenuBarExtra` cannot) and the `NSPopover` that hosts the UI.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var labelHostingView: NSHostingView<AnyView>?

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

        let rootView = AnyView(
            MenuBarLabel()
                .environment(store)
        )
        let host = NSHostingView(rootView: rootView)
        host.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
            host.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
            host.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            host.topAnchor.constraint(greaterThanOrEqualTo: button.topAnchor),
            host.bottomAnchor.constraint(lessThanOrEqualTo: button.bottomAnchor)
        ])
        labelHostingView = host
    }

    // MARK: Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
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
}
