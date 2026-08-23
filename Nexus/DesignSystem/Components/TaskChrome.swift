import SwiftUI
import NexusCore

/// Tinted project/task glyph without a colored tile behind it.
struct NexusProjectGlyph: View {
    let systemName: String
    let colorHex: String
    var size: CGFloat = NexusIconSize.glyph

    var body: some View {
        Image(systemName: systemName)
            .font(.body.weight(.medium))
            .foregroundStyle(NexusColor.from(hex: colorHex))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct PriorityBadge: View {
    let priority: TaskPriority

    var body: some View {
        if priority != .none {
            Text(priority.displayName)
                .font(NexusTypography.metadata)
                .foregroundStyle(tint)
                .accessibilityLabel(NexusL10n.format("task.priorityA11y", priority.displayName))
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
                .font(NexusTypography.metadata)
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
        return isOverdue ? "\(NexusL10n.tr("common.overdue")), \(base)" : base
    }
}

/// Compact secondary metadata: priority, due/overdue, checklist, subtasks.
struct NexusMetadataLine: View {
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
        HStack(spacing: NexusSpacing.xs) {
            if showStatus {
                Text(status.displayName)
                    .font(NexusTypography.metadata)
                    .foregroundStyle(.secondary)
            }
            if isOverdue {
                Text(NexusL10n.tr("common.overdue"))
                    .font(NexusTypography.metadata)
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
enum NexusStatusColor {
    static func indicator(for status: TaskStatus) -> Color {
        switch status {
        case .backlog:
            return Color(.systemGray)
        case .todo:
            return Color.accentColor
        case .inProgress:
            return Color.orange
        case .review:
            return Color.purple
        case .done:
            return Color.green
        }
    }
}

struct TaskStatusIndicator: View {
    let status: TaskStatus

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(NexusStatusColor.indicator(for: status))
            .frame(width: 3, height: 28)
            .accessibilityHidden(true)
    }
}
