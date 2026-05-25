import SwiftUI
import SwiftData

struct PortfolioPicker: View {
    @Binding var selectedId: String
    var onNew: () -> Void
    var onRename: (Portfolio) -> Void
    var onDelete: (Portfolio) -> Void

    @Environment(PortfolioStore.self) private var store

    var body: some View {
        let portfolios = store.allPortfolios()
        HStack(spacing: 4) {
            Picker("", selection: $selectedId) {
                if portfolios.isEmpty {
                    Text("（无组合）").tag("")
                }
                ForEach(portfolios) { p in
                    Text(p.name).tag(p.id.uuidString)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()

            Menu {
                Button("新建组合…", action: onNew)
                if let current = portfolios.first(where: { $0.id.uuidString == selectedId }) {
                    Divider()
                    Button("重命名…") { onRename(current) }
                    Button("删除", role: .destructive) { onDelete(current) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}
