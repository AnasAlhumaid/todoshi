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
    public let totalCount: Int
    public let projectID: UUID?
    public let projectIcon: String?
    public let projectColorHex: String?
    public let projectAvailability: WidgetProjectAvailability

    public init(
        generatedAt: Date = .now,
        title: String,
        tasks: [WidgetTaskItem],
        totalCount: Int,
        projectID: UUID? = nil,
        projectIcon: String? = nil,
        projectColorHex: String? = nil,
        projectAvailability: WidgetProjectAvailability = .available
    ) {
        self.generatedAt = generatedAt
        self.title = title
        self.tasks = tasks
        self.totalCount = totalCount
        self.projectID = projectID
        self.projectIcon = projectIcon
        self.projectColorHex = projectColorHex
        self.projectAvailability = projectAvailability
    }

    public static func unavailable(title: String, generatedAt: Date = .now) -> WidgetTaskSnapshot {
        WidgetTaskSnapshot(
            generatedAt: generatedAt,
            title: title,
            tasks: [],
            totalCount: 0,
            projectAvailability: .unavailable
        )
    }

    public static func needsConfiguration(generatedAt: Date = .now) -> WidgetTaskSnapshot {
        WidgetTaskSnapshot(
            generatedAt: generatedAt,
            title: NexusL10n.tr("common.project"),
            tasks: [],
            totalCount: 0,
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

    public init(id: UUID, name: String, icon: String, colorHex: String, position: Double) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.position = position
    }
}

/// Stable WidgetKit kind identifiers.
public enum NexusWidgetKind: Sendable {
    public static let today = "Nexus.TodayTasks"
    public static let highPriority = "Nexus.HighPriority"
    public static let project = "Nexus.ProjectTasks"
    public static let quickAddAccessory = "Nexus.QuickAddAccessory"
    public static let todayCountAccessory = "Nexus.TodayCountAccessory"

    public static var allTaskListKinds: [String] {
        [today, highPriority, project, todayCountAccessory]
    }

    public static var allKinds: [String] {
        allTaskListKinds + [quickAddAccessory]
    }
}
