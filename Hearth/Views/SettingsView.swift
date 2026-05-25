import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(PortfolioStore.self) private var store
    @Environment(QuoteRefresher.self) private var refresher

    @AppStorage("pinnedSlot1Id") private var slot1: String = ""
    @AppStorage("pinnedSlot2Id") private var slot2: String = ""
    @AppStorage("refreshIntervalSeconds") private var intervalSec: Int = 10
    @AppStorage("usQuoteProvider") private var usSourceRaw: String = USQuoteSource.yahoo.rawValue

    @State private var editingShortName: Portfolio?
    @State private var shortNameDraft: String = ""

    var body: some View {
        let portfolios = store.allPortfolios()
        VStack(alignment: .leading, spacing: 14) {
            Text("设置").font(.headline)

            section("菜单栏钉选") {
                HStack {
                    Text("第一行").frame(width: 56, alignment: .leading)
                    slotPicker(selection: $slot1, portfolios: portfolios)
                }
                HStack {
                    Text("第二行").frame(width: 56, alignment: .leading)
                    slotPicker(selection: $slot2, portfolios: portfolios)
                }
            }

            section("组合短名（菜单栏显示）") {
                if portfolios.isEmpty {
                    Text("还没有组合").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    ForEach(portfolios) { p in
                        HStack {
                            Text(p.name).frame(maxWidth: .infinity, alignment: .leading)
                            TextField("", text: shortNameBinding(for: p))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                    }
                }
            }

            section("刷新间隔") {
                Picker("", selection: $intervalSec) {
                    Text("5 秒").tag(5)
                    Text("10 秒").tag(10)
                    Text("30 秒").tag(30)
                    Text("60 秒").tag(60)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: intervalSec) { _, new in
                    refresher.interval = TimeInterval(new)
                }
            }

            section("美股数据源") {
                Picker("", selection: $usSourceRaw) {
                    ForEach(USQuoteSource.allCases) { s in
                        Text(s.displayName).tag(s.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: usSourceRaw) { _, new in
                    refresher.usSource = USQuoteSource(rawValue: new) ?? .yahoo
                }
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func slotPicker(selection: Binding<String>, portfolios: [Portfolio]) -> some View {
        Picker("", selection: selection) {
            Text("未选").tag("")
            ForEach(portfolios) { p in
                Text(p.name).tag(p.id.uuidString)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private func shortNameBinding(for p: Portfolio) -> Binding<String> {
        Binding(
            get: { p.shortName },
            set: {
                p.shortName = $0
                try? context.save()
            }
        )
    }
}
