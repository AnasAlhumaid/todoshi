import Foundation

/// Immutable widget presentation values — never live SwiftData models.
public struct WidgetTaskItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let projectID: UUID
    public let projectName: String
    public let projectIcon: String
    public let projectColorHex: String
    public let status: TaskStatus
    public let priority: TaskPriority
    public let dueDate: Date?
    public let isOverdue: Bool

    public init(
        id: UUID,
        title: String,
        projectID: UUID,
        projectName: String,
        projectIcon: String,
        projectColorHex: String,
        status: TaskStatus,
        priority: TaskPriority,
        dueDate: Date?,
        isOverdue: Bool
    ) {
        self.id = id
        self.title = title
        self.projectID = projectID
        self.projectName = projectName
        self.projectIcon = projectIcon
        self.projectColorHex = projectColorHex
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.isOverdue = isOverdue
    }
}

public enum WidgetProjectAvailability: Hashable, Sendable {
    case available
    case missingSelection
    case unavailable
}

public struct WidgetTaskSnapshot: Hashable, Sendable {
    public let generatedAt: Date
    public let title: String
    public let tasks: [WidgetTaskItem]
    /// Open tasks (Tasks) or remaining incomplete items (Checklist).
    public let totalCount: Int
    /// Total root items in the project (includes completed checklist rows).
    public let allRootCount: Int
    public let projectID: UUID?
    public let projectIcon: String?
    public let projectColorHex: String?
    public let projectType: ProjectType
    public let projectAvailability: WidgetProjectAvailability

    public init(
        generatedAt: Date = .now,
        title: String,
        tasks: [WidgetTaskItem],
        totalCount: Int,
        allRootCount: Int? = nil,
        projectID: UUID? = nil,
        projectIcon: String? = nil,
        projectColorHex: String? = nil,
        projectType: ProjectType = .tasks,
        projectAvailability: WidgetProjectAvailability = .available
    ) {
        self.generatedAt = generatedAt
        self.title = title
        self.tasks = tasks
        self.totalCount = totalCount
        self.allRootCount = allRootCount ?? totalCount
        self.projectID = projectID
        self.projectIcon = projectIcon
        self.projectColorHex = projectColorHex
        self.projectType = projectType
        self.projectAvailability = projectAvailability
    }

    public static func unavailable(title: String, generatedAt: Date = .now) -> WidgetTaskSnapshot {
        WidgetTaskSnapshot(
            generatedAt: generatedAt,
            title: title,
            tasks: [],
            totalCount: 0,
            allRootCount: 0,
            projectAvailability: .unavailable
        )
    }

    public static func needsConfiguration(generatedAt: Date = .now) -> WidgetTaskSnapshot {
        WidgetTaskSnapshot(
            generatedAt: generatedAt,
            title: TodoshiL10n.tr("common.project"),
            tasks: [],
            totalCount: 0,
            allRootCount: 0,
            projectAvailability: .missingSelection
        )
    }
}

public struct WidgetProjectOption: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let icon: String
    public let colorHex: String
    public let position: Double
    public let projectType: ProjectType

    public init(
        id: UUID,
        name: String,
        icon: String,
        colorHex: String,
        position: Double,
        projectType: ProjectType = .tasks
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.position = position
        self.projectType = projectType
    }
}

/// Stable WidgetKit kind identifiers.
public enum TodoshiWidgetKind: Sendable {
    public static let today = "Todoshi.TodayTasks"
    public static let highPriority = "Todoshi.HighPriority"
    public static let project = "Todoshi.ProjectTasks"
    public static let quickAddAccessory = "Todoshi.QuickAddAccessory"
    public static let todayCountAccessory = "Todoshi.TodayCountAccessory"

    public static var allTaskListKinds: [String] {
        [today, highPriority, project, todayCountAccessory]
    }

    public static var allKinds: [String] {
        allTaskListKinds + [quickAddAccessory]
    }
}
