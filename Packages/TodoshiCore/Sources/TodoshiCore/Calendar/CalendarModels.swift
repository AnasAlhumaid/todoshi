import Foundation

// MARK: - Source input (mapped from SwiftData once)


/// Immutable calendar input — never holds live SwiftData models.
public struct CalendarTaskSource: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let status: TaskStatus
    public let priority: TaskPriority
    public let dueDate: Date?
    public let completedAt: Date?
    public let updatedAt: Date
    public let position: Double
    public let isRoot: Bool
    public let isRecurring: Bool
    public let projectID: UUID
    public let projectName: String
    public let projectIcon: String
    public let projectColorHex: String
    public let projectIsActive: Bool
    public let checklistCompleted: Int
    public let checklistTotal: Int
    public let subtaskCompleted: Int
    public let subtaskTotal: Int

    public init(
        id: UUID,
        title: String,
        status: TaskStatus,
        priority: TaskPriority = .none,
        dueDate: Date? = nil,
        completedAt: Date? = nil,
        updatedAt: Date = .now,
        position: Double = FractionalPosition.initial(),
        isRoot: Bool = true,
        isRecurring: Bool = false,
        projectID: UUID,
        projectName: String,
        projectIcon: String = ProjectIconCatalog.defaultSymbol,
        projectColorHex: String = ProjectColorCatalog.defaultHex,
        projectIsActive: Bool = true,
        checklistCompleted: Int = 0,
        checklistTotal: Int = 0,
        subtaskCompleted: Int = 0,
        subtaskTotal: Int = 0
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.updatedAt = updatedAt
        self.position = position
        self.isRoot = isRoot
        self.isRecurring = isRecurring
        self.projectID = projectID
        self.projectName = projectName
        self.projectIcon = projectIcon
        self.projectColorHex = projectColorHex
        self.projectIsActive = projectIsActive
        self.checklistCompleted = checklistCompleted
        self.checklistTotal = checklistTotal
        self.subtaskCompleted = subtaskCompleted
        self.subtaskTotal = subtaskTotal
    }

    public var checklistProgress: ChecklistProgress? {
        checklistTotal > 0
            ? ChecklistProgress(completed: checklistCompleted, total: checklistTotal)
            : nil
    }

    public var subtaskProgress: SubtaskProgress? {
        subtaskTotal > 0
            ? SubtaskProgress(completed: subtaskCompleted, total: subtaskTotal)
            : nil
    }
}

// MARK: - Presentation values

public struct CalendarTaskItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let projectID: UUID
    public let projectName: String
    public let projectIcon: String
    public let projectColorHex: String
    public let dueDate: Date
    public let status: TaskStatus
    public let priority: TaskPriority
    public let position: Double
    public let updatedAt: Date
    public let isOverdue: Bool
    public let isRecurring: Bool
    public let checklistProgress: ChecklistProgress?
    public let subtaskProgress: SubtaskProgress?

    public init(
        id: UUID,
        title: String,
        projectID: UUID,
        projectName: String,
        projectIcon: String,
        projectColorHex: String,
        dueDate: Date,
        status: TaskStatus,
        priority: TaskPriority,
        position: Double = FractionalPosition.initial(),
        updatedAt: Date = .now,
        isOverdue: Bool,
        isRecurring: Bool,
        checklistProgress: ChecklistProgress? = nil,
        subtaskProgress: SubtaskProgress? = nil
    ) {
        self.id = id
        self.title = title
        self.projectID = projectID
        self.projectName = projectName
        self.projectIcon = projectIcon
        self.projectColorHex = projectColorHex
        self.dueDate = dueDate
        self.status = status
        self.priority = priority
        self.position = position
        self.updatedAt = updatedAt
        self.isOverdue = isOverdue
        self.isRecurring = isRecurring
        self.checklistProgress = checklistProgress
        self.subtaskProgress = subtaskProgress
    }
}

public struct CalendarDaySummary: Identifiable, Hashable, Sendable {
    public let date: Date
    public let openCount: Int
    public let completedCount: Int
    public let overdueOpenCount: Int

    public var id: Date { date }

    public var hasTasks: Bool {
        openCount + completedCount > 0
    }

    public init(date: Date, openCount: Int, completedCount: Int, overdueOpenCount: Int) {
        self.date = date
        self.openCount = openCount
        self.completedCount = completedCount
        self.overdueOpenCount = overdueOpenCount
    }
}

public struct CalendarDayAgenda: Equatable, Sendable {
    /// Tasks due on the selected day (open by default; optional completed when `includeCompleted`).
    public let dueOnDay: [CalendarTaskItem]
    /// Open overdue tasks — only populated when selected day is today.
    public let overdueWhenToday: [CalendarTaskItem]

    public init(dueOnDay: [CalendarTaskItem] = [], overdueWhenToday: [CalendarTaskItem] = []) {
        self.dueOnDay = dueOnDay
        self.overdueWhenToday = overdueWhenToday
    }

    public var isEmpty: Bool {
        dueOnDay.isEmpty && overdueWhenToday.isEmpty
    }
}

public enum UpcomingGroupKind: String, Hashable, CaseIterable, Sendable {
    case tomorrow
    case thisWeek
    case nextWeek
    case later

    public var title: String {
        switch self {
        case .tomorrow: return CalendarStrings.tomorrow
        case .thisWeek: return CalendarStrings.thisWeek
        case .nextWeek: return CalendarStrings.nextWeek
        case .later: return CalendarStrings.later
        }
    }
}

public struct UpcomingGroup: Identifiable, Hashable, Sendable {
    public let kind: UpcomingGroupKind
    public let tasks: [CalendarTaskItem]

    public var id: String { kind.rawValue }

    public init(kind: UpcomingGroupKind, tasks: [CalendarTaskItem]) {
        self.kind = kind
        self.tasks = tasks
    }
}

public struct CalendarMonthCell: Identifiable, Hashable, Sendable {
    public let date: Date?
    /// Day number when in-month; nil for padding cells.
    public let dayNumber: Int?
    public let isInMonth: Bool
    public let summary: CalendarDaySummary?

    public var id: String {
        if let date {
            return String(date.timeIntervalSinceReferenceDate)
        }
        return "pad-\(dayNumber ?? 0)-\(isInMonth)"
    }

    public init(date: Date?, dayNumber: Int?, isInMonth: Bool, summary: CalendarDaySummary?) {
        self.date = date
        self.dayNumber = dayNumber
        self.isInMonth = isInMonth
        self.summary = summary
    }
}
