import SwiftUI
import SwiftData
import TodoshiCore
import UIKit

struct KanbanColumnView: View {
    let status: TaskStatus
    let tasks: [TaskItem]
    let columnHeight: CGFloat
    let dragState: KanbanDragState
    let onAddTask: () -> Void
    let onEditTask: (TaskItem) -> Void
    let onDeleteTask: (TaskItem) -> Void
    let onMoveToStatus: (TaskItem, TaskStatus) -> Void
    let onMoveEarlier: (TaskItem) -> Void
    let onMoveLater: (TaskItem) -> Void
    let onCommitDrop: (UUID, TaskStatus, UUID?) -> Bool

    private let columnWidth: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: TodoshiSpacing.sm) {
            header
            cardsArea
        }
        .padding(.vertical, TodoshiSpacing.xs)
        .padding(.horizontal, TodoshiSpacing.xs)
        .frame(width: columnWidth, height: columnHeight, alignment: .top)
        .background {
            if dragState.highlightedStatus == status {
                RoundedRectangle(cornerRadius: TodoshiRadius.md, style: .continuous)
                    .fill(Color.accentColor.opacity(0.06))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: TodoshiRadius.md, style: .continuous)
                .strokeBorder(
                    dragState.highlightedStatus == status ? Color.accentColor.opacity(0.45) : Color.clear,
                    lineWidth: 1.5
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(TodoshiL10n.format("kanban.statusCount", status.displayName, tasks.count))
    }

    private var header: some View {
        HStack(spacing: TodoshiSpacing.xs) {
            Text(status.displayName)
                .font(TodoshiTypography.section)
            Text("\(tasks.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(action: onAddTask) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 32, minHeight: 32)
            }
            .accessibilityLabel(TodoshiL10n.format("a11y.addTaskTo", status.displayName))
        }
    }

    private var cardsArea: some View {
        ScrollView {
            LazyVStack(spacing: TodoshiSpacing.sm) {
                ForEach(tasks, id: \.id) { task in
                    card(for: task)
                }
                endDropZone
            }
            .padding(.bottom, TodoshiSpacing.sm)
        }
        .scrollIndicators(.hidden)
        .dropDestination(for: String.self) { items, _ in
            handleColumnDrop(items, before: nil)
        } isTargeted: { targeted in
            updateColumnHighlight(targeted: targeted, atEnd: tasks.isEmpty)
        }
    }

    private func card(for task: TaskItem) -> some View {
        KanbanTaskCardView(
            task: task,
            isLifted: dragState.draggedTaskID == task.id,
            isInsertionTarget: dragState.insertionTargetID == task.id && dragState.highlightedStatus == status,
            onMoveToStatus: { onMoveToStatus(task, $0) },
            onMoveEarlier: { onMoveEarlier(task) },
            onMoveLater: { onMoveLater(task) },
            onEdit: { onEditTask(task) },
            onDelete: { onDeleteTask(task) }
        )
        .draggable(task.id.uuidString) {
            cardContentPreview(task)
                .frame(width: columnWidth - 32)
                .onAppear { dragState.draggedTaskID = task.id }
                .onDisappear {
                    if dragState.draggedTaskID == task.id {
                        dragState.draggedTaskID = nil
                    }
                }
        }
        .dropDestination(for: String.self) { items, _ in
            handleColumnDrop(items, before: task.id)
        } isTargeted: { targeted in
            if targeted {
                dragState.highlightedStatus = status
                dragState.insertionTargetID = task.id
                dragState.insertAtEndOfHighlighted = false
            } else if dragState.insertionTargetID == task.id {
                dragState.insertionTargetID = nil
            }
        }
    }

    private func cardContentPreview(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: TodoshiSpacing.xs) {
            Text(task.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)
            if task.priority != .none {
                PriorityBadge(priority: task.priority)
            }
        }
        .padding(TodoshiSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: TodoshiRadius.md, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
        .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
    }

    private var endDropZone: some View {
        Group {
            if tasks.isEmpty {
                Text(TodoshiL10n.tr("kanban.dropHere"))
                    .font(TodoshiTypography.metadata)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                Color.clear.frame(height: 28)
            }
        }
            .dropDestination(for: String.self) { items, _ in
                handleColumnDrop(items, before: nil)
            } isTargeted: { targeted in
                updateColumnHighlight(targeted: targeted, atEnd: true)
            }
            .accessibilityLabel(
                tasks.isEmpty
                    ? TodoshiL10n.format("kanban.emptyDrop", status.displayName)
                    : TodoshiL10n.format("kanban.endOf", status.displayName)
            )
    }

    private func handleColumnDrop(_ items: [String], before: UUID?) -> Bool {
        guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
        _ = onCommitDrop(id, status, before)
        dragState.clear()
        return true
    }

    private func updateColumnHighlight(targeted: Bool, atEnd: Bool) {
        if targeted {
            dragState.highlightedStatus = status
            if atEnd {
                dragState.insertionTargetID = nil
                dragState.insertAtEndOfHighlighted = true
            }
        } else if dragState.highlightedStatus == status, atEnd {
            dragState.highlightedStatus = nil
            dragState.insertAtEndOfHighlighted = false
        }
    }
}
