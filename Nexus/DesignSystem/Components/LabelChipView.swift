import SwiftUI
import NexusCore

/// Compact colored label chip used across rows, detail, and pickers.
struct LabelChipView: View {
    let name: String
    let colorHex: String
    var compact: Bool = false

    var body: some View {
        HStack(spacing: NexusSpacing.xxs) {
            Circle()
                .fill(NexusColor.from(hex: colorHex))
                .frame(width: compact ? 6 : 7, height: compact ? 6 : 7)
                .accessibilityHidden(true)
            Text(name)
                .font(compact ? .caption2 : NexusTypography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 3)
        .background(NexusColor.from(hex: colorHex).opacity(0.10))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(NexusL10n.format("label.chipA11y", name, LabelColorCatalog.name(for: colorHex)))
    }
}

struct LabelChipsFlow: View {
    let labels: [(id: UUID, name: String, colorHex: String)]
    var maxVisible: Int = 2
    var compact: Bool = true

    var body: some View {
        let visible = Array(labels.prefix(maxVisible))
        let overflow = labels.count - visible.count
        HStack(spacing: NexusSpacing.xxs) {
            ForEach(visible, id: \.id) { item in
                LabelChipView(name: item.name, colorHex: item.colorHex, compact: compact)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(NexusL10n.format("label.moreA11y", overflow))
            }
        }
    }
}
