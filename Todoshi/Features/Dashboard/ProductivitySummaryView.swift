import SwiftUI
import NexusCore

struct ProductivitySummaryView: View {
    let metrics: ProductivityMetrics.Snapshot

    var body: some View {
        HStack(spacing: NexusSpacing.xs) {
            compactMetric(metrics.completedToday, NexusL10n.tr("metrics.doneToday"))
            dot
            compactMetric(metrics.openRootTasks, NexusL10n.tr("metrics.open"))
            if metrics.overdueRootTasks > 0 {
                dot
                compactMetric(metrics.overdueRootTasks, NexusL10n.tr("metrics.overdue"), emphasize: true)
            }
            Spacer(minLength: 0)
        }
        .font(NexusTypography.metadata)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            NexusL10n.format(
                "metrics.productivityA11y",
                metrics.completedToday,
                metrics.completedThisWeek,
                metrics.openRootTasks,
                metrics.overdueRootTasks
            )
        )
    }

    private var dot: some View {
        Text("·")
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private func compactMetric(_ value: Int, _ title: String, emphasize: Bool = false) -> some View {
        Text("\(value) \(title)")
            .foregroundStyle(emphasize ? Color.red : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
