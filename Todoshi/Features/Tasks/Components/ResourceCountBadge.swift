import SwiftUI
import TodoshiCore

struct ResourceCountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            HStack(spacing: 3) {
                Image(systemName: "paperclip")
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TodoshiL10n.format("resource.countA11y", count))
        }
    }
}
