import Foundation

/// Product shape of a Todoshi project. Immutable after creation (Phase 8).
public enum ProjectType: String, Codable, Sendable, CaseIterable, Identifiable {
    case tasks
    case checklist

    public var id: String { rawValue }

    /// Legacy projects without a stored type behave as Tasks.
    public static let legacyDefault: ProjectType = .tasks

    public static func resolve(_ raw: String?) -> ProjectType {
        guard let raw, let value = ProjectType(rawValue: raw) else {
            return .legacyDefault
        }
        return value
    }
}

/// Feature surface for each project type. Keep narrow — not a generic feature-flag engine.
public enum ProjectTypeCapabilities: Sendable {
    public static func supportsBoard(_ type: ProjectType) -> Bool {
        type == .tasks
    }

    public static func supportsSubtasks(_ type: ProjectType) -> Bool {
        type == .tasks
    }

    public static func supportsNestedChecklist(_ type: ProjectType) -> Bool {
        type == .tasks
    }

    public static func supportsResources(_ type: ProjectType) -> Bool {
        type == .tasks
    }

    public static func supportsWorkflowStatuses(_ type: ProjectType) -> Bool {
        type == .tasks
    }

    public static func allowedStatuses(for type: ProjectType) -> [TaskStatus] {
        switch type {
        case .tasks:
            return Array(TaskStatus.allCases)
        case .checklist:
            return [.todo, .inProgress, .done]
        }
    }

    public static func allowsStatus(_ status: TaskStatus, for type: ProjectType) -> Bool {
        allowedStatuses(for: type).contains(status)
    }

    /// New checklist items always start as Not Started.
    public static func defaultStatus(for type: ProjectType) -> TaskStatus {
        switch type {
        case .tasks: return .todo
        case .checklist: return .todo
        }
    }

    public static func defaultIcon(for type: ProjectType) -> String {
        switch type {
        case .tasks: return ProjectIconCatalog.defaultSymbol
        case .checklist: return "checklist"
        }
    }

    /// Project type cannot change after creation.
    public static func canChangeType(from: ProjectType, to: ProjectType) -> Bool {
        from == to
    }
}

/// Status labels that respect the active project type.
public enum ProjectStatusPolicy: Sendable {
    public static func displayName(_ status: TaskStatus, for type: ProjectType) -> String {
        switch type {
        case .tasks:
            return status.displayName
        case .checklist:
            switch status {
            case .todo: return TodoshiL10n.tr("project.checklist.status.todo")
            case .inProgress: return TodoshiL10n.tr("project.checklist.status.inProgress")
            case .done: return TodoshiL10n.tr("project.checklist.status.done")
            case .backlog, .review:
                // Invalid for checklist; fall back to the Tasks label if ever shown.
                return status.displayName
            }
        }
    }

    /// Preferred cycle for a simple checklist tap: todo → inProgress → done.
    /// Completed items do not cycle back via the same primary control.
    public static func nextChecklistCycle(from status: TaskStatus) -> TaskStatus? {
        switch status {
        case .todo: return .inProgress
        case .inProgress: return .done
        case .done, .backlog, .review: return nil
        }
    }

    /// Statuses counted in Checklist member progress (excludes backlog/review).
    public static func progressStatuses(for type: ProjectType) -> [TaskStatus] {
        switch type {
        case .tasks: return Array(TaskStatus.allCases)
        case .checklist: return [.todo, .inProgress, .done]
        }
    }
}

/// User-facing copy that differs between Tasks and Checklist projects.
public enum ProjectTerminologyPolicy: Sendable {
    public static func typeTitle(_ type: ProjectType) -> String {
        switch type {
        case .tasks: return TodoshiL10n.tr("project.type.tasks")
        case .checklist: return TodoshiL10n.tr("project.type.checklist")
        }
    }

    public static func typeSubtitle(_ type: ProjectType) -> String {
        switch type {
        case .tasks: return TodoshiL10n.tr("project.type.tasks.subtitle")
        case .checklist: return TodoshiL10n.tr("project.type.checklist.subtitle")
        }
    }

    public static var chooseTypeTitle: String {
        TodoshiL10n.tr("project.type.chooseTitle")
    }

    public static func addItem(_ type: ProjectType) -> String {
        switch type {
        case .tasks: return TodoshiL10n.tr("calendar.addTask")
        case .checklist: return TodoshiL10n.tr("project.checklist.addItem")
        }
    }

    public static func addItemPlaceholder(_ type: ProjectType) -> String {
        switch type {
        case .tasks: return TodoshiL10n.tr("form.taskTitle")
        case .checklist: return TodoshiL10n.tr("project.checklist.addPlaceholder")
        }
    }

    public static func emptyTitle(_ type: ProjectType) -> String {
        switch type {
        case .tasks: return TodoshiL10n.tr("project.noTasks")
        case .checklist: return TodoshiL10n.tr("project.checklist.emptyTitle")
        }
    }

    public static func emptyMessage(_ type: ProjectType) -> String {
        switch type {
        case .tasks: return TodoshiL10n.tr("project.noTasks")
        case .checklist: return TodoshiL10n.tr("project.checklist.emptyMessage")
        }
    }

    public static func allFilter(_ type: ProjectType) -> String {
        switch type {
        case .tasks: return TodoshiL10n.tr("task.assignment.allTasks")
        case .checklist: return TodoshiL10n.tr("project.checklist.allItems")
        }
    }

    public static func mineFilter(_ type: ProjectType) -> String {
        switch type {
        case .tasks: return TodoshiL10n.tr("task.assignment.myTasks")
        case .checklist: return TodoshiL10n.tr("project.checklist.myItems")
        }
    }

    public static func assignedSection(_ type: ProjectType) -> String {
        switch type {
        case .tasks: return TodoshiL10n.tr("task.assignment.assignedTasks")
        case .checklist: return TodoshiL10n.tr("project.checklist.assignedItems")
        }
    }

    public static func completedGroup(_ count: Int) -> String {
        TodoshiL10n.format("project.checklist.completedCount", count)
    }

    public static func remainingSummary(remaining: Int, inProgress: Int, completed: Int) -> String {
        TodoshiL10n.format(
            "project.checklist.summary",
            remaining,
            inProgress,
            completed
        )
    }

    public static func openItemsCount(_ count: Int) -> String {
        TodoshiL10n.plural("project.checklist.openItemsCount", count: count)
    }

    public static func noEditPermission(for type: ProjectType) -> String {
        switch type {
        case .tasks: return SharedTaskPermissionPresentation.noEditPermission
        case .checklist: return TodoshiL10n.tr("project.checklist.noEdit")
        }
    }
}
