import SwiftUI
import SwiftData

/// Inline form for editing an existing holding's shares and cost price.
/// Symbol/market intentionally read-only — changing those would mean it's a
/// different position entirely, so delete + re-add is the right flow.
struct EditHoldingForm: View {
    let holding: Holding
    var onCancel: () -> Void
    var onSaved: () -> Void

    @Environment(PortfolioStore.self) private var store

    @State private var sharesText: String
    @State private var costText: String

    init(holding: Holding, onCancel: @escaping () -> Void, onSaved: @escaping () -> Void) {
        self.holding = holding
        self.onCancel = onCancel
        self.onSaved = onSaved
        _sharesText = State(initialValue: Self.numString(holding.shares))
        _costText = State(initialValue: Self.numString(holding.costPrice))
    }

    private var canSave: Bool {
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
                Text("编辑")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text(store.quotes[holding.key]?.name ?? holding.symbol)
                    .font(.system(size: 13, weight: .medium))
                Text(holding.symbol)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(holding.market.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
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

    private func save() {
        guard let s = Double(sharesText), let c = Double(costText) else { return }
        holding.shares = s
        holding.costPrice = c
        // Save through the holding's own context — it lives in the store's
        // ModelContext, not in the popover's @Environment one.
        try? holding.modelContext?.save()
        onSaved()
    }

    private static func numString(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", v)
        }
        return String(format: "%g", v)
    }
}
