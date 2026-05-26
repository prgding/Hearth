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

    @AppStorage("lastSelectedPortfolioId") private var selectedId: String = ""

    @State private var nameDraft: String = ""

    var body: some View {
        let portfolios = store.allPortfolios()
        let current = portfolios.first(where: { $0.id.uuidString == selectedId })
            ?? portfolios.first

        VStack(alignment: .leading, spacing: 0) {
            switch nav.page {
            case .list:
                header(current: current, portfolios: portfolios)
                Divider()
                content(current: current)
                Divider()
                footer(current: current)
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
        .onAppear {
            if selectedId.isEmpty, let first = portfolios.first {
                selectedId = first.id.uuidString
            }
        }
    }

    // MARK: List page chunks

    @ViewBuilder
    private func header(current: Portfolio?, portfolios: [Portfolio]) -> some View {
        HStack(spacing: 8) {
            PortfolioPicker(
                selectedId: Binding(
                    get: { current?.id.uuidString ?? selectedId },
                    set: { selectedId = $0 }
                ),
                onNew: {
                    nameDraft = ""
                    nav.page = .newPortfolio
                },
                onRename: { p in
                    nameDraft = p.name
                    nav.page = .renamePortfolio(portfolioId: p.id.uuidString)
                },
                onDelete: { p in deletePortfolio(p) }
            )

            Spacer(minLength: 8)

            if let p = current {
                summary(for: p)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func summary(for p: Portfolio) -> some View {
        let pnl = store.todayPnL(for: p)
        let pct = store.todayPnLPercent(for: p)
        let total = store.totalPnL(for: p)
        VStack(alignment: .trailing, spacing: 1) {
            Text(PnLFormatter.amountString(pnl))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                Text(PnLFormatter.percentString(pct))
                Text("浮盈 \(PnLFormatter.amountString(total))")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 10, design: .monospaced))
        }
    }

    @ViewBuilder
    private func content(current: Portfolio?) -> some View {
        if let p = current {
            if p.holdings.isEmpty {
                emptyState(
                    message: "该组合里还没股票",
                    action: { nav.page = .addHolding(portfolioId: p.id.uuidString) },
                    label: "添加股票"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedHoldings(p)) { h in
                            HoldingRow(holding: h, quote: store.quotes[h.key])
                                .padding(.horizontal, 12)
                                .contextMenu {
                                    Button("编辑") {
                                        nav.page = .editHolding(holdingId: h.persistentModelID)
                                    }
                                    Button("删除", role: .destructive) {
                                        context.delete(h)
                                        try? context.save()
                                    }
                                }
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
        } else {
            emptyState(
                message: "还没有组合",
                action: { nameDraft = ""; nav.page = .newPortfolio },
                label: "新建组合"
            )
        }
    }

    @ViewBuilder
    private func footer(current: Portfolio?) -> some View {
        HStack(spacing: 8) {
            Button {
                if let p = current {
                    nav.page = .addHolding(portfolioId: p.id.uuidString)
                }
            } label: {
                Label("添加股票", systemImage: "plus")
            }
            .disabled(current == nil)

            Spacer()

            if let ts = store.lastRefreshAt {
                Text("更新于 \(timeString(ts))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else if let err = store.lastError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }

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
        selectedId = p.id.uuidString
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
        context.delete(p)
        try? context.save()
        selectedId = store.allPortfolios().first?.id.uuidString ?? ""
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
