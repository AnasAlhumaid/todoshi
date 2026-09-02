import SwiftUI
import NexusCore

struct ProjectBoardTaskCardView: View {
    let task: HomeTaskSummary
    let sectionStatus: TaskStatus
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMoveToStatus: (TaskStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NexusSpacing.xs) {
            NavigationLink(value: AppRoute.task(task.id)) {
                VStack(alignment: .leading, spacing: NexusSpacing.xxs) {
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
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

            TaskStatusControl(
                currentStatus: task.status,
                style: TaskStatusControl.style(for: task.status, sectionStatus: sectionStatus),
                sectionStatus: sectionStatus,
                onSelect: onMoveToStatus
            )
        }
        .padding(NexusSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: NexusRadius.md, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
        .contextMenu { contextMenuContent }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        NavigationLink(value: AppRoute.task(task.id)) {
            Text(NexusL10n.tr("kanban.openTask"))
        }
        if let shortcut = TaskStatusShortcuts.primary(from: task.status),
           shortcut.target != task.status {
            Button(shortcut.label()) {
                onMoveToStatus(shortcut.target)
            }
        }
        Button(NexusL10n.tr("common.edit"), action: onEdit)
        Button(NexusL10n.tr("common.delete"), role: .destructive, action: onDelete)
    }

    private var hasMetadata: Bool {
        task.priority != .none
            || task.dueDate != nil
            || task.isOverdue
            || task.checklistProgress != nil
            || task.subtaskProgress != nil
    }
}
