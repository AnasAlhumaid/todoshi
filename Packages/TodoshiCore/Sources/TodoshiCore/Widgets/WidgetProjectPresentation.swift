import Foundation

/// Project-type-specific widget copy and deep-link helpers for the Project Tasks widget.
public enum WidgetProjectPresentation: Sendable {
    public static func primaryCountText(remaining: Int, projectType: ProjectType) -> String {
        switch projectType {
        case .tasks:
            return TodoshiL10n.plural("widget.openTasksCount", count: remaining)
        case .checklist:
            return TodoshiL10n.plural("widget.itemsRemainingCount", count: remaining)
        }
    }

    public static func addActionTitle(for projectType: ProjectType) -> String {
        switch projectType {
        case .tasks:
            return TodoshiL10n.tr("widget.addTask")
        case .checklist:
            return TodoshiL10n.tr("widget.addItem")
        }
    }

    public static func openActionTitle(for projectType: ProjectType) -> String {
        switch projectType {
        case .tasks:
            return TodoshiL10n.tr("widget.openProject")
        case .checklist:
            return TodoshiL10n.tr("widget.openList")
        }
    }

    public static func emptyTitle(for projectType: ProjectType) -> String {
        switch projectType {
        case .tasks:
            return TodoshiL10n.tr("widget.noOpenTasks")
        case .checklist:
            return TodoshiL10n.tr("widget.noItems")
        }
    }

    public static func emptySubtitle(for projectType: ProjectType) -> String {
        switch projectType {
        case .tasks:
            return TodoshiL10n.tr("widget.noOpenTasksHint")
        case .checklist:
            return TodoshiL10n.tr("widget.noItemsHint")
        }
    }

    public static func addAccessibilityLabel(projectName: String, projectType: ProjectType) -> String {
        switch projectType {
        case .tasks:
            return TodoshiL10n.format("widget.addTaskTo", projectName)
        case .checklist:
            return TodoshiL10n.format("widget.addItemTo", projectName)
        }
    }

    public static func statusLabel(_ status: TaskStatus, projectType: ProjectType) -> String {
        ProjectStatusPolicy.displayName(status, for: projectType)
    }

    public static func openCountAccessibilityLabel(title: String, remaining: Int, projectType: ProjectType) -> String {
        TodoshiL10n.format("widget.a11yOpenCount", title, remaining)
    }

    public static func taskRowAccessibilityLabel(
        title: String,
        status: TaskStatus,
        projectType: ProjectType,
        priority: TaskPriority,
        isOverdue: Bool
    ) -> String {
        let statusName = statusLabel(status, projectType: projectType)
        var parts = [title, statusName]
        if projectType == .tasks {
            if priority == .urgent || priority == .high {
                parts.append(priority.displayName)
            }
            if isOverdue {
                parts.append(TodoshiL10n.tr("common.overdue"))
            }
        }
        return parts.joined(separator: ", ")
    }

    public static func isProjectWidgetEmpty(
        projectType: ProjectType,
        remainingCount: Int,
        allRootCount: Int
    ) -> Bool {
        switch projectType {
        case .tasks:
            return remainingCount == 0
        case .checklist:
            return allRootCount == 0
        }
    }
}
