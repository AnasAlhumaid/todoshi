import SwiftUI
import TodoshiCore

/// Tinted project/task glyph without a colored tile behind it.
struct TodoshiProjectGlyph: View {
    let systemName: String
    let colorHex: String
    var size: CGFloat = TodoshiIconSize.glyph

    var body: some View {
        Image(systemName: systemName)
            .font(.body.weight(.medium))
            .foregroundStyle(TodoshiColor.from(hex: colorHex))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct PriorityBadge: View {
    let priority: TaskPriority

    var body: some View {
        if priority == .high || priority == .urgent {
            Image(systemName: "flag.fill")
                .font(.caption2)
                .foregroundStyle(tint)
                .accessibilityLabel(TodoshiL10n.format("task.priorityA11y", priority.displayName))
        }
    }

    private var tint: Color {
        switch priority {
        case .none: return .secondary
        case .low: return .secondary
        case .medium: return .orange
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

struct DueDateLabel: View {
    let dueDate: Date?
    let status: TaskStatus
    var showTime: Bool = false

    var body: some View {
        if let dueDate {
            Text(dueDate, style: showTime ? .time : .date)
                .font(TodoshiTypography.metadata)
                .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                .accessibilityLabel(accessibilityText)
        }
    }

    private var isOverdue: Bool {
        TaskPredicates.isOverdue(dueDate, status: status)
    }

    private var accessibilityText: String {
        guard let dueDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        if showTime { formatter.timeStyle = .short }
        let base = formatter.string(from: dueDate)
        return isOverdue ? "\(TodoshiL10n.tr("common.overdue")), \(base)" : base
    }
}

/// Compact secondary metadata: priority, due/overdue, checklist, subtasks.
struct TodoshiMetadataLine: View {
    var priority: TaskPriority = .none
    var dueDate: Date? = nil
    var status: TaskStatus = .todo
    var isOverdue: Bool = false
    var showTime: Bool = false
    var showStatus: Bool = false
    var checklist: ChecklistProgress? = nil
    var subtasks: SubtaskProgress? = nil
    var resourceCount: Int = 0

    var body: some View {
        HStack(spacing: TodoshiSpacing.xs) {
            if showStatus {
                Text(status.displayName)
                    .font(TodoshiTypography.metadata)
                    .foregroundStyle(.secondary)
            }
            if isOverdue {
                Text(TodoshiL10n.tr("common.overdue"))
                    .font(TodoshiTypography.metadata)
                    .foregroundStyle(.red)
            } else {
                DueDateLabel(dueDate: dueDate, status: status, showTime: showTime)
            }
            PriorityBadge(priority: priority)
            if let checklist {
                ChecklistProgressBadge(progress: checklist)
            }
            if let subtasks {
                SubtaskProgressBadge(progress: subtasks)
            }
            ResourceCountBadge(count: resourceCount)
        }
        .lineLimit(1)
    }
}

/// Semantic status colors for compact indicators (Dark Mode safe).
enum TodoshiStatusColor {
    static func indicator(for status: TaskStatus) -> Color {
        switch status {
        case .backlog:
            return Color(.systemGray)
        case .todo:
            return TodoshiBrand.accent
        case .inProgress:
            return Color.orange
        case .review:
            return Color(red: 0.55, green: 0.36, blue: 0.85)
        case .done:
            return Color.green
        }
    }
}

/// Subtle unread collaboration marker for shared project task/checklist rows.
struct TaskUnreadActivityMarker: View {
    var body: some View {
        Text(TaskCollaborationActivityPresentation.unreadBadge)
            .font(TodoshiTypography.metadata.weight(.semibold))
            .foregroundStyle(TodoshiBrand.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(TodoshiBrand.accentMuted, in: Capsule())
            .accessibilityLabel(TodoshiL10n.tr("task.activity.new"))
    }
}

struct TaskStatusIndicator: View {
    let status: TaskStatus

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(TodoshiStatusColor.indicator(for: status))
            .frame(width: 3, height: 28)
            .accessibilityHidden(true)
    }
}

/// Small circular initial for a task's assignee.
struct TodoshiInitialAvatar: View {
    let name: String
    var size: CGFloat = 22

    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(.system(size: size * 0.48, weight: .semibold, design: .rounded))
            .foregroundStyle(TodoshiBrand.accent)
            .frame(width: size, height: size)
            .background(TodoshiBrand.accentMuted, in: Circle())
    }
}

/// Round tap target that completes a task; filled when done, red ring when overdue.
struct TodoshiCompletionCircle: View {
    let isDone: Bool
    var isOverdue: Bool = false
    var size: CGFloat = 24
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(ringColor, lineWidth: 2)
                    .background(Circle().fill(isDone ? Color.green : .clear))
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .frame(width: TodoshiIconSize.hit, height: TodoshiIconSize.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: isDone) { _, new in new }
        .accessibilityLabel(TodoshiL10n.tr(isDone ? "status.done" : "task.markDone"))
    }

    private var ringColor: Color {
        if isDone { return .green }
        return isOverdue ? .red : Color.secondary.opacity(0.5)
    }
}
