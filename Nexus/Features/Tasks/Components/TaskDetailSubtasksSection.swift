import SwiftUI
import SwiftData
import UIKit
import NexusCore

/// Immediate subtask list for root Task Detail (full children are TaskItems).
struct TaskDetailSubtasksSection: View {
    let parent: TaskItem
    var onError: (String) -> Void
    var onAddSubtask: (UUID, UUID) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var isReordering = false

    private var ordered: [TaskItem] {
        TaskHierarchyPolicy.orderedSubtasks(parent.subtasks ?? [])
    }

    private var progress: SubtaskProgress {
        SubtaskProgress.from(tasks: ordered)
    }

    var body: some View {
        Section {
            SubtaskProgressHeader(progress: progress)

            if ordered.isEmpty {
                Text(SubtaskStrings.noSubtasks)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(ordered, id: \.id) { child in
                    subtaskRow(child)
                }
                .onMove { source, destination in
                    reorder(from: source, to: destination)
                }
            }

            Button {
                guard let projectID = parent.project?.id else { return }
                onAddSubtask(parent.id, projectID)
            } label: {
                Label(SubtaskStrings.addSubtask, systemImage: "plus.circle")
            }
            .accessibilityLabel(SubtaskStrings.addSubtask)
        } header: {
            HStack {
                Text(SubtaskStrings.subtasks)
                Spacer()
                if ordered.count > 1 {
                    Button(isReordering ? NexusL10n.tr("common.done") : NexusL10n.tr("subtask.reorder")) {
                        isReordering.toggle()
                    }
                    .font(.caption.weight(.semibold))
                    .accessibilityLabel(isReordering ? NexusL10n.tr("subtask.doneReorder") : NexusL10n.tr("subtask.reorder"))
                }
            }
        }
        .environment(\.editMode, .constant(isReordering ? .active : .inactive))
    }

    @ViewBuilder
    private func subtaskRow(_ child: TaskItem) -> some View {
        let index = (ordered.firstIndex(where: { $0.id == child.id }) ?? 0) + 1
        let total = ordered.count
        let checklist = ChecklistProgress.from(completedFlags: (child.checklist ?? []).map(\.isCompleted))

        NavigationLink(value: AppRoute.task(child.id)) {
            HStack(alignment: .top, spacing: NexusSpacing.sm) {
                Button {
                    toggleCompletion(child)
                } label: {
                    Image(systemName: child.status == .done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(child.status == .done ? Color.accentColor : .secondary)
                        .imageScale(.large)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    child.status == .done ? NexusL10n.tr("checklist.markIncomplete") : NexusL10n.tr("checklist.markComplete")
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(child.title)
                        .font(.body.weight(.medium))
                        .strikethrough(child.status == .done, color: .secondary)
                        .foregroundStyle(child.status == .done ? .secondary : .primary)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: NexusSpacing.sm) {
                        Text(child.status.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if child.priority != .none {
                            PriorityBadge(priority: child.priority)
                        }
                        DueDateLabel(dueDate: child.dueDate, status: child.status)
                        if child.reminderDate != nil {
                            Image(systemName: "bell.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(NexusL10n.tr("task.hasReminder"))
                        }
                        ChecklistProgressBadge(progress: checklist)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: child, index: index, total: total))
    }

    private func accessibilityLabel(for child: TaskItem, index: Int, total: Int) -> String {
        var parts = [
            child.title,
            "subtask",
            child.status.displayName
        ]
        if child.priority != .none {
            parts.append(child.priority.displayName)
        }
        parts.append("\(index) of \(total)")
        return parts.joined(separator: ", ")
    }

    private func toggleCompletion(_ child: TaskItem) {
        let repo = TaskRepository(context: modelContext)
        do {
            if child.status == .done {
                try repo.reopen(child)
            } else {
                try repo.complete(child)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            onError(UserFacingError.message(for: error))
        }
    }

    private func reorder(from source: IndexSet, to destination: Int) {
        guard let from = source.first else { return }
        var ids = ordered.map(\.id)
        let moved = ids[from]
        ids.move(fromOffsets: source, toOffset: destination)
        guard let newIndex = ids.firstIndex(of: moved) else { return }
        let beforeID = newIndex + 1 < ids.count ? ids[newIndex + 1] : nil
        do {
            _ = try TaskRepository(context: modelContext).reorderSubtask(
                taskID: moved,
                before: beforeID
            )
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            onError(UserFacingError.message(for: error))
        }
    }
}

/// Parent context banner for child task detail.
struct TaskDetailParentContextSection: View {
    let parent: TaskItem
    let projectName: String?
    var onPromote: () -> Void

    var body: some View {
        Section {
            NavigationLink(value: AppRoute.task(parent.id)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(SubtaskStrings.subtaskOf)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(parent.title)
                        .font(.body.weight(.semibold))
                    if let projectName {
                        Text(projectName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityLabel("\(SubtaskStrings.subtaskOf) \(parent.title)")

            Button(SubtaskStrings.promoteToRoot, action: onPromote)
                .accessibilityLabel(SubtaskStrings.promoteToRoot)
        } header: {
            Text(SubtaskStrings.parentTask)
        }
    }
}
