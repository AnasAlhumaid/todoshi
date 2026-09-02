import Foundation

public struct HomeLabelSummary: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let colorHex: String

    public init(id: UUID, name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

public struct HomeTaskSummary: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let title: String
    public let status: TaskStatus
    public let priority: TaskPriority
    public let dueDate: Date?
    public let position: Double
    public let createdAt: Date
    public let checklistProgress: ChecklistProgress?
    public let subtaskProgress: SubtaskProgress?
    public let labels: [HomeLabelSummary]
    public let isOverdue: Bool

    public init(
        id: UUID,
        projectID: UUID,
        title: String,
        status: TaskStatus,
        priority: TaskPriority,
        dueDate: Date?,
        position: Double,
        createdAt: Date,
        checklistProgress: ChecklistProgress? = nil,
        subtaskProgress: SubtaskProgress? = nil,
        labels: [HomeLabelSummary] = [],
        isOverdue: Bool = false
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.position = position
        self.createdAt = createdAt
        self.checklistProgress = checklistProgress
        self.subtaskProgress = subtaskProgress
        self.labels = labels
        self.isOverdue = isOverdue
    }

    public func accessibilityLabel(locale: Locale = .autoupdatingCurrent) -> String {
        var parts = [title, status.displayName(locale: locale)]
        if priority != .none {
            parts.append(NexusL10n.format("task.priorityA11y", locale: locale, priority.displayName(locale: locale)))
        }
        if isOverdue {
            parts.append(NexusL10n.tr("common.overdue", locale: locale))
        }
        if !labels.isEmpty {
            parts.append(labels.map(\.name).joined(separator: ", "))
        }
        if let checklistProgress, checklistProgress.hasProgress {
            parts.append(checklistProgress.accessibilityLabel)
        }
        if let subtaskProgress, subtaskProgress.hasProgress {
            parts.append(subtaskProgress.accessibilityLabel)
        }
        return parts.joined(separator: ", ")
    }
}

public struct HomeProjectSummary: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let icon: String
    public let colorHex: String
    public let projectDescription: String
    public let position: Double
    public let createdAt: Date
    public let openTaskCount: Int
    public let tasks: [HomeTaskSummary]

    public init(
        id: UUID,
        name: String,
        icon: String,
        colorHex: String,
        projectDescription: String,
        position: Double,
        createdAt: Date,
        openTaskCount: Int,
        tasks: [HomeTaskSummary]
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.projectDescription = projectDescription
        self.position = position
        self.createdAt = createdAt
        self.openTaskCount = openTaskCount
        self.tasks = tasks
    }
}

/// Home tab task ordering: actionable statuses first, then fractional position.
public enum HomeTaskOrdering: Sendable {
    public static let statusPrecedence: [TaskStatus] = [.inProgress, .review, .todo, .backlog]

    public static func sort(_ tasks: [HomeTaskSummary]) -> [HomeTaskSummary] {
        tasks.sorted(by: areInOrder)
    }

    public static func areInOrder(_ lhs: HomeTaskSummary, _ rhs: HomeTaskSummary) -> Bool {
        let leftIndex = statusPrecedence.firstIndex(of: lhs.status) ?? Int.max
        let rightIndex = statusPrecedence.firstIndex(of: rhs.status) ?? Int.max
        if leftIndex != rightIndex { return leftIndex < rightIndex }
        if lhs.position != rhs.position { return lhs.position < rhs.position }
        return lhs.createdAt < rhs.createdAt
    }
}
