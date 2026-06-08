import SwiftUI
import SwiftData
import Observation

/// State machine for the popover content. We can't use `.sheet` or `.popover`
/// inside `MenuBarExtra(.window)` — any child window steals focus and forces
/// the popover to dismiss. So all "modal" UIs are inline pages instead.
enum PopoverPage: Equatable {
    case list
    case settings
    case addHolding(portfolioId: String)
    case editHolding(holdingId: PersistentIdentifier)
    case newPortfolio
    case renamePortfolio(portfolioId: String)
}

/// Lifted out of `@State` so AppDelegate's NSEvent key monitor can read/write
/// the current page. We need to handle ESC at the AppKit level — SwiftUI's
/// `.keyboardShortcut(.escape)` stops firing once the popover's NSWindow has
/// been closed and reshown with a TextField focused, because AppKit's default
/// `cancelOperation:` (close window) runs before SwiftUI sees the key.
@MainActor
@Observable
final class PopoverNavigator {
    var page: PopoverPage = .list
}

struct MenuBarPopover: View {
    @Environment(\.modelContext) private var context
    @Environment(PortfolioStore.self) private var store
    @Environment(QuoteRefresher.self) private var refresher
    @Environment(PopoverNavigator.self) private var nav

    @State private var nameDraft: String = ""

    /// Collapsed portfolio IDs. Loaded once from UserDefaults (the @State
    /// initializer runs when the hosting controller first builds the view —
    /// it survives popover open/close cycles) and rewritten on every toggle.
    @State private var collapsed: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: Self.collapsedKey) ?? []
    )

    private static let collapsedKey = "collapsedPortfolioIds"

    var body: some View {
        let portfolios = store.allPortfolios()

        VStack(alignment: .leading, spacing: 0) {
            switch nav.page {
            case .list:
                listTopBar()
                Divider()
                listContent(portfolios: portfolios)
                Divider()
                listFooter()
            case .settings:
                pageHeader(title: "设置")
                Divider()
                ScrollView { SettingsView() }
            case .addHolding(let pid):
                if let p = store.portfolio(id: pid) {
                    AddHoldingForm(
                        portfolio: p,
                        onCancel: { nav.page = .list },
                        onSaved: { nav.page = .list }
                    )
                } else {
                    Text("组合已删除").foregroundStyle(.secondary).padding()
                }
            case .editHolding(let hid):
                if let h = store.holding(id: hid) {
                    EditHoldingForm(
                        holding: h,
                        onCancel: { nav.page = .list },
                        onSaved: { nav.page = .list }
                    )
                } else {
                    Text("持仓已删除").foregroundStyle(.secondary).padding()
                }
            case .newPortfolio:
                PortfolioNameForm(
                    title: "新建组合",
                    confirmLabel: "创建",
                    name: $nameDraft,
                    onCancel: { nav.page = .list },
                    onConfirm: { createPortfolio() }
                )
            case .renamePortfolio(let pid):
                PortfolioNameForm(
                    title: "重命名",
                    confirmLabel: "保存",
                    name: $nameDraft,
                    onCancel: { nav.page = .list },
                    onConfirm: { renamePortfolio(id: pid) }
                )
            }
        }
        .frame(width: 380, height: 500)
        .background {
            Button("", action: { refresher.refreshNow() })
                .keyboardShortcut("r", modifiers: .command)
                .hidden()
        }
    }

    // MARK: List page chunks

    @ViewBuilder
    private func listTopBar() -> some View {
        HStack {
            Button {
                nameDraft = ""
                nav.page = .newPortfolio
            } label: {
                Label("新建组合", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func listContent(portfolios: [Portfolio]) -> some View {
        if portfolios.isEmpty {
            emptyState(
                message: "还没有组合",
                action: { nameDraft = ""; nav.page = .newPortfolio },
                label: "新建组合"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(portfolios) { p in
                        portfolioSection(p)
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func portfolioSection(_ p: Portfolio) -> some View {
        let isCollapsed = collapsed.contains(p.id.uuidString)
        portfolioHeader(p, isCollapsed: isCollapsed)
            .contentShape(Rectangle())
            .onTapGesture { toggleCollapse(p.id.uuidString) }
            .contextMenu {
                Button("添加股票") {
                    nav.page = .addHolding(portfolioId: p.id.uuidString)
                }
                Button("重命名") {
                    nameDraft = p.name
                    nav.page = .renamePortfolio(portfolioId: p.id.uuidString)
                }
                Divider()
                Button("删除", role: .destructive) { deletePortfolio(p) }
            }
        if !isCollapsed {
            if p.holdings.isEmpty {
                emptyHoldingsRow(for: p)
            } else {
                ForEach(sortedHoldings(p)) { h in
                    HoldingRow(holding: h, quote: store.quotes[h.key])
                        .padding(.horizontal, 12)
                        .padding(.leading, 12)
                        .contextMenu {
                            Button("编辑") {
                                nav.page = .editHolding(holdingId: h.persistentModelID)
                            }
                            Button("删除", role: .destructive) {
                                context.delete(h)
                                try? context.save()
                            }
                        }
                    Divider().padding(.leading, 24)
                }
            }
        }
    }

    @ViewBuilder
    private func portfolioHeader(_ p: Portfolio, isCollapsed: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 10)
            Text(p.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            summary(for: p)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func summary(for p: Portfolio) -> some View {
        let pnl = store.todayPnL(for: p)
        let pct = store.todayPnLPercent(for: p)
        let value = store.marketValue(for: p)
        let total = store.totalPnL(for: p)
        HStack(alignment: .top, spacing: 10) {
            // Left: today's PnL over today's change percent.
            VStack(alignment: .trailing, spacing: 1) {
                Text(PnLFormatter.amountString(pnl))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                Text(PnLFormatter.percentString(pct))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            // Right: total market value over total floating PnL.
            VStack(alignment: .trailing, spacing: 1) {
                Text(PnLFormatter.valueString(value))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                Text("浮盈 \(PnLFormatter.amountString(total))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func emptyHoldingsRow(for p: Portfolio) -> some View {
        HStack {
            Text("该组合里还没股票")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("添加股票") {
                nav.page = .addHolding(portfolioId: p.id.uuidString)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.leading, 18)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func listFooter() -> some View {
        HStack(spacing: 8) {
            if let ts = store.lastRefreshAt {
                Text("更新于 \(timeString(ts))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else if let err = store.lastError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }

            Spacer()

            Button {
                nav.page = .settings
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("设置")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("退出 Hearth")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func toggleCollapse(_ id: String) {
        if collapsed.contains(id) {
            collapsed.remove(id)
        } else {
            collapsed.insert(id)
        }
        UserDefaults.standard.set(Array(collapsed), forKey: Self.collapsedKey)
    }

    @ViewBuilder
    private func emptyState(message: String, action: (() -> Void)?, label: String?) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if let action, let label {
                Button(label, action: action)
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func pageHeader(title: String) -> some View {
        HStack {
            Button {
                nav.page = .list
            } label: {
                Image(systemName: "chevron.left")
                Text("返回")
            }
            .buttonStyle(.borderless)
            Spacer()
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            Color.clear.frame(width: 50, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Actions

    private func createPortfolio() {
        let name = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let count = store.allPortfolios().count
        let p = Portfolio(name: name, orderIndex: count)
        context.insert(p)
        try? context.save()
        nav.page = .list
    }

    private func renamePortfolio(id: String) {
        guard let p = store.portfolio(id: id) else { nav.page = .list; return }
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if p.shortName == p.name || p.shortName.isEmpty {
            p.shortName = trimmed
        }
        p.name = trimmed
        try? context.save()
        nav.page = .list
    }

    private func deletePortfolio(_ p: Portfolio) {
        let id = p.id.uuidString
        context.delete(p)
        try? context.save()
        collapsed.remove(id)
        UserDefaults.standard.set(Array(collapsed), forKey: Self.collapsedKey)
    }

    private func sortedHoldings(_ p: Portfolio) -> [Holding] {
        p.holdings.sorted { $0.addedAt < $1.addedAt }
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
}
