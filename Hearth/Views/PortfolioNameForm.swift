import SwiftUI

/// Inline form for creating or renaming a portfolio (no sheet — MenuBarExtra
/// popover would dismiss itself when a child window steals focus).
struct PortfolioNameForm: View {
    let title: String
    let confirmLabel: String
    @Binding var name: String
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button(confirmLabel) {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    onConfirm()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }
}
