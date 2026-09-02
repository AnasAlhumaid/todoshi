import SwiftUI
import NexusCore

struct HomeTaskRowView: View {
    let task: HomeTaskSummary
    var onMoveToStatus: ((TaskStatus) -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: NexusSpacing.sm) {
            if let onMoveToStatus {
                TaskStatusControl(
                    currentStatus: task.status,
                    style: .homeIndicator,
                    onSelect: onMoveToStatus
                )
            } else {
                TaskStatusIndicator(status: task.status)
            }

            NavigationLink(value: AppRoute.task(task.id)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if hasMetadata {
                        NexusMetadataLine(
                            priority: task.priority,
                            dueDate: task.dueDate,
                            status: task.status,
                            isOverdue: task.isOverdue,
                            checklist: task.checklistProgress,
                            subtasks: task.subtaskProgress
                        )
                    }

                    if !task.labels.isEmpty {
                        LabelChipsFlow(
                            labels: task.labels.map { (id: $0.id, name: $0.name, colorHex: $0.colorHex) },
                            maxVisible: 2,
                            compact: true
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint(NexusL10n.tr("kanban.opensDetails"))
        }
        .frame(minHeight: NexusIconSize.hit, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var hasMetadata: Bool {
        task.priority != .none
            || task.dueDate != nil
            || task.isOverdue
            || task.checklistProgress != nil
            || task.subtaskProgress != nil
    }
}
