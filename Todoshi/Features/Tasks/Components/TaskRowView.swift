import SwiftUI
import NexusCore

/// Shared task row: title, optional context, compact metadata, up to two labels.
struct NexusTaskRow: View {
    let title: String
    var isCompleted: Bool = false
    var context: String? = nil
    var projectIcon: String? = nil
    var projectColorHex: String? = nil
    var showsProjectGlyph: Bool = true
    var priority: TaskPriority = .none
    var dueDate: Date? = nil
    var status: TaskStatus = .todo
    var isOverdue: Bool = false
    var showTime: Bool = false
    var showStatus: Bool = false
    var isRecurring: Bool = false
    var labels: [(id: UUID, name: String, colorHex: String)] = []
    var checklist: ChecklistProgress? = nil
    var subtasks: SubtaskProgress? = nil
    var resourceCount: Int = 0
    var showsLabels: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: NexusSpacing.sm) {
            if showsProjectGlyph, let icon = projectIcon, let hex = projectColorHex {
                NexusProjectGlyph(systemName: icon, colorHex: hex, size: NexusIconSize.glyph)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: NexusSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: NexusSpacing.xs) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(isCompleted ? Color.secondary : Color.primary)
                        .strikethrough(isCompleted)
                        .lineLimit(2)
                    if isRecurring {
                        Image(systemName: "repeat")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel(NexusL10n.tr("calendar.recurringTask"))
                    }
                }

                if let context, !context.isEmpty {
                    Text(context)
                        .font(NexusTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                NexusMetadataLine(
                    priority: priority,
                    dueDate: dueDate,
                    status: status,
                    isOverdue: isOverdue,
                    showTime: showTime,
                    showStatus: showStatus,
                    checklist: checklist,
                    subtasks: subtasks,
                    resourceCount: resourceCount
                )

                if showsLabels, !labels.isEmpty {
                    LabelChipsFlow(labels: labels, maxVisible: 2, compact: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, NexusSpacing.xxs)
        .frame(minHeight: 44, alignment: .top)
        .opacity(isCompleted ? 0.78 : 1)
        .accessibilityElement(children: .combine)
    }
}

struct TaskRowView: View {
    let task: TaskItem
    var showsProjectContext: Bool = false

    var body: some View {
        NexusTaskRow(
            title: task.title,
            isCompleted: task.status == .done,
            context: showsProjectContext ? task.project?.name : nil,
            projectIcon: task.project?.icon,
            projectColorHex: task.project?.colorHex,
            showsProjectGlyph: showsProjectContext,
            priority: task.priority,
            dueDate: task.dueDate,
            status: task.status,
            isOverdue: TaskPredicates.isOverdue(task.dueDate, status: task.status),
            labels: labelTuples,
            checklist: checklistProgress.hasProgress ? checklistProgress : nil,
            subtasks: subtaskProgress.hasProgress ? subtaskProgress : nil,
            resourceCount: (task.resources ?? []).count
        )
        .accessibilityLabel(accessibilityLabel)
    }

    private var labelTuples: [(id: UUID, name: String, colorHex: String)] {
        (task.labels ?? [])
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { (id: $0.id, name: $0.name, colorHex: $0.colorHex) }
    }

    private var checklistProgress: ChecklistProgress {
        ChecklistProgress.from(completedFlags: (task.checklist ?? []).map(\.isCompleted))
    }

    private var subtaskProgress: SubtaskProgress {
        SubtaskProgress.from(tasks: task.subtasks ?? [])
    }

    private var accessibilityLabel: String {
        var parts = [task.title, task.status.displayName]
        if task.priority != .none {
            parts.append(task.priority.displayName)
        }
        if !labelTuples.isEmpty {
            parts.append(labelTuples.map(\.name).joined(separator: ", "))
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
