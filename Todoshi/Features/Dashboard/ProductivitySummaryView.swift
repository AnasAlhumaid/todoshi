import SwiftUI
import TodoshiCore

struct ProductivitySummaryView: View {
    let metrics: ProductivityMetrics.Snapshot

    var body: some View {
        HStack(spacing: TodoshiSpacing.xs) {
            compactMetric(metrics.completedToday, TodoshiL10n.tr("metrics.doneToday"))
            dot
            compactMetric(metrics.openRootTasks, TodoshiL10n.tr("metrics.open"))
            if metrics.overdueRootTasks > 0 {
                dot
                compactMetric(metrics.overdueRootTasks, TodoshiL10n.tr("metrics.overdue"), emphasize: true)
            }
            Spacer(minLength: 0)
        }
        .font(TodoshiTypography.metadata)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            TodoshiL10n.format(
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
