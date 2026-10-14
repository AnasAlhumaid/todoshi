import SwiftUI
import TodoshiCore

struct HomeTaskRowView: View {
    let task: HomeTaskSummary
    var onMoveToStatus: ((TaskStatus) -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: TodoshiSpacing.xs) {
            NavigationLink(value: AppRoute.task(task.id)) {
                taskContent
                    .frame(maxWidth: .infinity, minHeight: NavigationHitTargetPolicy.minimumRowHitHeightPoints, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.title)
            .accessibilityHint(TodoshiL10n.tr("kanban.opensDetails"))

            if let onMoveToStatus {
                TaskStatusControl(
                    currentStatus: task.status,
                    style: .homeIndicator,
                    onSelect: onMoveToStatus
                )
            }
        }
        .padding(.vertical, TodoshiSpacing.xxs)
        .accessibilityElement(children: .contain)
    }

    private var taskContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: TodoshiSpacing.xs) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if task.hasUnreadActivity {
                    TaskUnreadActivityMarker()
                }
            }

            if hasExtraMetadata {
                TodoshiMetadataLine(
                    priority: task.priority,
                    dueDate: task.dueDate,
                    status: task.status,
                    isOverdue: task.isOverdue,
                    subtasks: task.subtaskProgress
                )
            }
        }
    }

    private var hasExtraMetadata: Bool {
        task.priority == .high || task.priority == .urgent
            || task.dueDate != nil
            || task.isOverdue
            || task.subtaskProgress != nil
    }
}
