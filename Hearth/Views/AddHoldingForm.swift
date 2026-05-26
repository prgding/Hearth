import SwiftUI
import SwiftData

/// Inline form for adding a holding to a portfolio. NOT a sheet — see
/// MenuBarExtra(.window) constraint discussed in MenuBarPopover.
struct AddHoldingForm: View {
    let portfolio: Portfolio
    var onCancel: () -> Void
    var onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(PortfolioStore.self) private var store

    @AppStorage("usQuoteProvider") private var usSourceRaw: String = USQuoteSource.yahoo.rawValue

    @State private var rawSymbol: String = ""
    @State private var market: Market = .aShare
    @State private var sharesText: String = ""
    @State private var costText: String = ""
    @State private var probeResult: ProbeState = .idle
    @State private var probing = false

    enum ProbeState: Equatable {
        case idle
        case success(name: String, last: Double)
        case failed
    }

    private var usSource: USQuoteSource {
        USQuoteSource(rawValue: usSourceRaw) ?? .yahoo
    }

    private var canSave: Bool {
        guard case .success = probeResult else { return false }
        guard let s = Double(sharesText), s > 0 else { return false }
        guard let c = Double(costText), c > 0 else { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "chevron.left")
                    Text("返回")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("添加到「\(portfolio.name)」")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Picker("市场", selection: $market) {
                ForEach(Market.allCases) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: market) { _, _ in probeResult = .idle }

            TextField(market == .aShare ? "代码（如 600519）" : "代码（如 AAPL）",
                      text: $rawSymbol)
                .textFieldStyle(.roundedBorder)
                .onChange(of: rawSymbol) { _, _ in probeResult = .idle }

            HStack(spacing: 8) {
                Button {
                    Task { await probe() }
                } label: {
                    if probing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("测试行情")
                    }
                }
                .disabled(rawSymbol.isEmpty || probing)
                probeResultView
                Spacer()
            }

            HStack(spacing: 8) {
                TextField("股数", text: $sharesText)
                    .textFieldStyle(.roundedBorder)
                TextField("成本价", text: $costText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") { save() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var probeResultView: some View {
        switch probeResult {
        case .idle:
            EmptyView()
        case .success(let name, let last):
            Text("\(name)  \(String(format: "%.2f", last))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.green)
                .lineLimit(1)
        case .failed:
            Text("未找到该代码")
                .font(.system(size: 11))
                .foregroundStyle(.red)
        }
    }

    private func probe() async {
        let canonical = SymbolNormalizer.canonical(rawSymbol, market: market)
        guard !canonical.isEmpty else { return }
        probing = true
        defer { probing = false }
        let key = SymbolKey(market: market, symbol: canonical)
        if let q = await store.probe(key, usSource: usSource) {
            probeResult = .success(name: q.name, last: q.last)
        } else {
            probeResult = .failed
        }
    }

    private func save() {
        guard case .success = probeResult else { return }
        guard let s = Double(sharesText), let c = Double(costText) else { return }
        let canonical = SymbolNormalizer.canonical(rawSymbol, market: market)
        let h = Holding(symbol: canonical, market: market, shares: s, costPrice: c)
        h.portfolio = portfolio
        context.insert(h)
        try? context.save()
        onSaved()
    }
}
