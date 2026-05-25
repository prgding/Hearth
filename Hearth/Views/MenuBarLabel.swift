import SwiftUI

struct MenuBarLabel: View {
    @AppStorage("pinnedSlot1Id") private var slot1: String = ""
    @AppStorage("pinnedSlot2Id") private var slot2: String = ""
    @AppStorage("menuBarColorStyle") private var colorStyleRaw: String = MenuBarColorStyle.pnl.rawValue
    @Environment(PortfolioStore.self) private var store

    private var colorStyle: MenuBarColorStyle {
        MenuBarColorStyle(rawValue: colorStyleRaw) ?? .pnl
    }

    var body: some View {
        let p1 = store.portfolio(id: slot1.isEmpty ? nil : slot1)
        let p2 = store.portfolio(id: slot2.isEmpty ? nil : slot2)

        if p1 == nil && p2 == nil {
            Image(systemName: "chart.line.uptrend.xyaxis")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                rowText(p1)
                rowText(p2)
            }
            .fixedSize()
        }
    }

    @ViewBuilder
    private func rowText(_ portfolio: Portfolio?) -> some View {
        if let p = portfolio {
            let pnl = store.todayPnL(for: p)
            Text("\(p.shortName):\(PnLFormatter.amountString(pnl))")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(textColor(for: pnl))
                .lineLimit(1)
        } else {
            Text("未选")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func textColor(for pnl: Double) -> Color {
        switch colorStyle {
        case .pnl: PnLColor.of(pnl)
        case .system: .primary
        }
    }
}
