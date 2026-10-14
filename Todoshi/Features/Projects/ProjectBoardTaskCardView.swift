import SwiftUI
import TodoshiCore

struct ProjectBoardTaskCardView: View {
    let task: HomeTaskSummary
    let column: ProjectColumn
    let columns: [ProjectColumn]
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMoveToColumn: (ProjectColumn) -> Void

    @Environment(\.layoutDirection) private var layoutDirection
    @State private var dragOffset: CGFloat = 0

    private static let swipeThreshold: CGFloat = 90

    private var columnIndex: Int? { columns.firstIndex { $0.id == column.id } }

    private var nextColumn: ProjectColumn? {
        guard let index = columnIndex, index + 1 < columns.count else { return nil }
        return columns[index + 1]
    }

    private var previousColumn: ProjectColumn? {
        guard let index = columnIndex, index > 0 else { return nil }
        return columns[index - 1]
    }

    private var isDone: Bool { column.kind == .done }

    private var isUrgent: Bool { task.priority == .urgent || task.priority == .high }

    var body: some View {
        NavigationLink(value: AppRoute.task(task.id)) {
            VStack(alignment: .leading, spacing: TodoshiSpacing.xs) {
                if isUrgent {
                    Text(TodoshiL10n.tr("task.urgent"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, TodoshiSpacing.xs)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.1), in: Capsule())
                }

                HStack(alignment: .firstTextBaseline, spacing: TodoshiSpacing.xs) {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .strikethrough(isDone)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if task.hasUnreadActivity {
                        TaskUnreadActivityMarker()
                    }
                }

                if hasFooter {
                    footer
                }
            }
            .padding(TodoshiSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .todoshiSurface(cornerRadius: TodoshiRadius.lg + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: dragOffset)
        .simultaneousGesture(swipeGesture)
        .contextMenu { contextMenuContent }
        .accessibilityElement(children: .combine)
        .accessibilityHint(TodoshiL10n.tr("kanban.opensDetails"))
        .accessibilityActions {
            if let next = nextColumn {
                Button(next.name) { onMoveToColumn(next) }
            }
            if let previous = previousColumn {
                Button(previous.name) { onMoveToColumn(previous) }
            }
        }
    }

    private var hasFooter: Bool {
        task.dueDate != nil || task.isOverdue || task.subtaskProgress != nil || task.assigneeDisplayName != nil
    }

    private var footer: some View {
        HStack(spacing: TodoshiSpacing.sm) {
            if let subtasks = task.subtaskProgress {
                SubtaskProgressBadge(progress: subtasks)
            }
            if task.isOverdue {
                Label(TodoshiL10n.tr("common.overdue"), systemImage: "clock")
                    .font(TodoshiTypography.metadata)
                    .foregroundStyle(.red)
            } else if task.dueDate != nil {
                HStack(spacing: 3) {
                    Image(systemName: "calendar")
                        .font(TodoshiTypography.metadata)
                        .foregroundStyle(.secondary)
                    DueDateLabel(dueDate: task.dueDate, status: task.status)
                }
            }
            Spacer(minLength: 0)
            if let assignee = task.assigneeDisplayName {
                TodoshiInitialAvatar(name: assignee, size: 26)
                    .accessibilityLabel("\(TaskAssignmentPresentation.assigneeLabel): \(assignee)")
            }
        }
    }

    /// Horizontal swipe moves the card one column forward (toward the trailing edge) or back.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
                dragOffset = value.translation.width * 0.6
            }
            .onEnded { value in
                defer { withAnimation(.snappy) { dragOffset = 0 } }
                guard abs(value.translation.width) > abs(value.translation.height) * 2,
                      abs(value.translation.width) > Self.swipeThreshold else { return }
                // Translation is in screen space; in RTL the "forward" direction is leftward.
                let towardTrailing = layoutDirection == .rightToLeft
                    ? value.translation.width < 0
                    : value.translation.width > 0
                if let target = towardTrailing ? nextColumn : previousColumn {
                    TodoshiHaptics.taskStatusChanged(crossStatus: target.kind != column.kind)
                    onMoveToColumn(target)
                }
            }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        ForEach(columns.filter { $0.id != column.id }) { target in
            Button {
                onMoveToColumn(target)
            } label: {
                Label(target.name, systemImage: target.kind == .done ? "checkmark.circle" : "arrow.left.arrow.right")
            }
        }
        Divider()
        Button(TodoshiL10n.tr("common.edit"), action: onEdit)
        Button(TodoshiL10n.tr("common.delete"), role: .destructive, action: onDelete)
    }
}
