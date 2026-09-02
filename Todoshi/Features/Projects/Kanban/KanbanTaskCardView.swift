import SwiftUI
import NexusCore

struct KanbanTaskCardView: View {
    let task: TaskItem
    let isLifted: Bool
    let isInsertionTarget: Bool
    let onMoveToStatus: (TaskStatus) -> Void
    let onMoveEarlier: () -> Void
    let onMoveLater: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        cardLink
            .contextMenu { contextMenuContent }
    }

    private var cardLink: some View {
        NavigationLink(value: AppRoute.task(task.id)) {
            cardContent
        }
        .buttonStyle(.plain)
        .modifier(KanbanTaskCardAccessibility(
            label: accessibilityLabel,
            onEdit: onEdit,
            onDelete: onDelete,
            onMoveEarlier: onMoveEarlier,
            onMoveLater: onMoveLater,
            onMoveToStatus: onMoveToStatus
        ))
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        NavigationLink(value: AppRoute.task(task.id)) {
            Text(NexusL10n.tr("kanban.openTask"))
        }
        Menu(NexusL10n.tr("task.moveToStatus")) {
            ForEach(TaskStatus.allCases, id: \.self) { status in
                Button(status.displayName) {
                    onMoveToStatus(status)
                }
                .disabled(status == task.status)
            }
        }
        Button(NexusL10n.tr("common.edit"), action: onEdit)
        Button(NexusL10n.tr("common.delete"), role: .destructive, action: onDelete)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: NexusSpacing.xxs) {
            HStack(alignment: .top, spacing: NexusSpacing.xs) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                Spacer(minLength: 4)
            }

            NexusMetadataLine(
                priority: task.priority,
                dueDate: task.dueDate,
                status: task.status,
                isOverdue: TaskPredicates.isOverdue(task.dueDate, status: task.status),
                checklist: checklistProgress.hasProgress ? checklistProgress : nil,
                subtasks: subtaskProgress.hasProgress ? subtaskProgress : nil
            )

            let labelTuples = (task.labels ?? [])
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { (id: $0.id, name: $0.name, colorHex: $0.colorHex) }
            if !labelTuples.isEmpty {
                LabelChipsFlow(labels: labelTuples, maxVisible: 2, compact: true)
            }
        }
        .padding(NexusSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: NexusRadius.md, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
        .overlay {
            if isInsertionTarget {
                RoundedRectangle(cornerRadius: NexusRadius.md, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.85), lineWidth: 2)
            }
        }
        .scaleEffect(liftScale)
        .shadow(color: isLifted ? .black.opacity(0.10) : .clear, radius: isLifted ? 4 : 0, y: 1)
    }

    private var checklistProgress: ChecklistProgress {
        ChecklistProgress.from(completedFlags: (task.checklist ?? []).map(\.isCompleted))
    }

    private var subtaskProgress: SubtaskProgress {
        SubtaskProgress.from(tasks: task.subtasks ?? [])
    }

    private var liftScale: CGFloat {
        guard isLifted, !reduceMotion else { return 1 }
        return 1.02
    }

    private var accessibilityLabel: String {
        var parts = [task.title, task.status.displayName]
        if task.priority != .none {
            parts.append("Priority \(task.priority.displayName)")
        }
        if TaskPredicates.isOverdue(task.dueDate, status: task.status) {
            parts.append(NexusL10n.tr("common.overdue"))
        }
        if task.status == .done {
            parts.append(NexusL10n.tr("a11y.completed"))
        }
        let names = (task.labels ?? []).map(\.name).sorted()
        if !names.isEmpty {
            parts.append(names.joined(separator: ", "))
        }
        if subtaskProgress.hasProgress {
            parts.append(subtaskProgress.accessibilityLabel)
        }
        if checklistProgress.hasProgress {
            parts.append(checklistProgress.accessibilityLabel)
        }
        return parts.joined(separator: ", ")
    }
}

/// Isolated accessibility modifiers so the card body type-checks quickly.
private struct KanbanTaskCardAccessibility: ViewModifier {
    let label: String
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMoveEarlier: () -> Void
    let onMoveLater: () -> Void
    let onMoveToStatus: (TaskStatus) -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHint(NexusL10n.tr("kanban.opensDetails"))
            .accessibilityAction(named: NexusL10n.tr("common.edit"), onEdit)
            .accessibilityAction(named: NexusL10n.tr("common.delete"), onDelete)
            .accessibilityAction(named: NexusL10n.tr("kanban.moveEarlier"), onMoveEarlier)
            .accessibilityAction(named: NexusL10n.tr("kanban.moveLater"), onMoveLater)
            .accessibilityAction(named: Text(NexusL10n.format("kanban.moveTo", TaskStatus.backlog.displayName))) {
                onMoveToStatus(.backlog)
            }
            .accessibilityAction(named: Text(NexusL10n.format("kanban.moveTo", TaskStatus.todo.displayName))) {
                onMoveToStatus(.todo)
            }
            .accessibilityAction(named: Text(NexusL10n.format("kanban.moveTo", TaskStatus.inProgress.displayName))) {
                onMoveToStatus(.inProgress)
            }
            .accessibilityAction(named: Text(NexusL10n.format("kanban.moveTo", TaskStatus.review.displayName))) {
                onMoveToStatus(.review)
            }
            .accessibilityAction(named: Text(NexusL10n.format("kanban.moveTo", TaskStatus.done.displayName))) {
                onMoveToStatus(.done)
            }
    }
}
