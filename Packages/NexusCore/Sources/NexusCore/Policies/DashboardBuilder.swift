import Foundation

/// Lightweight task input for pure dashboard section building (tests + app).
public struct DashboardTaskInput: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let status: TaskStatus
    public let priority: TaskPriority
    public let dueDate: Date?
    public let completedAt: Date?
    public let updatedAt: Date
    public let position: Double
    public let isRoot: Bool
    public let projectID: UUID
    public let projectName: String
    public let projectIcon: String
    public let projectColorHex: String
    public let projectIsActive: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        status: TaskStatus,
        priority: TaskPriority = .none,
        dueDate: Date? = nil,
        completedAt: Date? = nil,
        updatedAt: Date = .now,
        position: Double = FractionalPosition.initial(),
        isRoot: Bool = true,
        projectID: UUID,
        projectName: String,
        projectIcon: String = ProjectIconCatalog.defaultSymbol,
        projectColorHex: String = ProjectColorCatalog.defaultHex,
        projectIsActive: Bool = true
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
        self.projectID = projectID
        self.projectName = projectName
        self.projectIcon = projectIcon
        self.projectColorHex = projectColorHex
        self.projectIsActive = projectIsActive
    }
}

public struct DashboardProjectInput: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let icon: String
    public let colorHex: String
    public let projectDescription: String
    public let position: Double
    public let status: ProjectStatus
    public let openRootCount: Int
    public let totalRootCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = ProjectIconCatalog.defaultSymbol,
        colorHex: String = ProjectColorCatalog.defaultHex,
        projectDescription: String = "",
        position: Double,
        status: ProjectStatus = .active,
        openRootCount: Int,
        totalRootCount: Int
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.projectDescription = projectDescription
        self.position = position
        self.status = status
        self.openRootCount = openRootCount
        self.totalRootCount = totalRootCount
    }
}

public struct DashboardSnapshot: Equatable, Sendable {
    public var metrics: ProductivityMetrics.Snapshot
    public var dueToday: [DashboardTaskInput]
    public var overdue: [DashboardTaskInput]
    public var overdueTotalCount: Int
    public var recentlyUpdated: [DashboardTaskInput]
    public var activeProjects: [DashboardProjectInput]
    public var activeProjectTotalCount: Int

    public init(
        metrics: ProductivityMetrics.Snapshot = .init(),
        dueToday: [DashboardTaskInput] = [],
        overdue: [DashboardTaskInput] = [],
        overdueTotalCount: Int = 0,
        recentlyUpdated: [DashboardTaskInput] = [],
        activeProjects: [DashboardProjectInput] = [],
        activeProjectTotalCount: Int = 0
    ) {
        self.metrics = metrics
        self.dueToday = dueToday
        self.overdue = overdue
        self.overdueTotalCount = overdueTotalCount
        self.recentlyUpdated = recentlyUpdated
        self.activeProjects = activeProjects
        self.activeProjectTotalCount = activeProjectTotalCount
    }
}

public enum DashboardBuilder: Sendable {
    public static let defaultOverduePreviewLimit = 5
    public static let defaultRecentLimit = 5
    public static let defaultActiveProjectsLimit = 5

    public static func build(
        projects: [DashboardProjectInput],
        tasks: [DashboardTaskInput],
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now,
        overduePreviewLimit: Int = defaultOverduePreviewLimit,
        recentLimit: Int = defaultRecentLimit,
        activeProjectsLimit: Int = defaultActiveProjectsLimit
    ) -> DashboardSnapshot {
        let activeProjects = projects
            .filter { $0.status == .active }
            .sorted {
                if $0.position != $1.position { return $0.position < $1.position }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        let activeProjectIDs = Set(activeProjects.map(\.id))

        let eligibleRoot = tasks.filter {
            $0.isRoot && $0.projectIsActive && activeProjectIDs.contains($0.projectID)
        }

        let metrics = ProductivityMetrics.snapshot(
            rootTasks: eligibleRoot,
            calendar: calendar,
            now: now
        )

        let dueToday = eligibleRoot
            .filter {
                TaskPredicates.isDueToday($0.dueDate, status: $0.status, calendar: calendar, now: now)
            }
            .sorted(by: dueTodaySort)

        let overdueAll = eligibleRoot
            .filter {
                TaskPredicates.isOverdue($0.dueDate, status: $0.status, calendar: calendar, now: now)
            }
            .sorted(by: overdueSort)

        let dueOrOverdueIDs = Set(dueToday.map(\.id)).union(overdueAll.map(\.id))

        let recentlyUpdated = eligibleRoot
            .filter { $0.status != .done && !dueOrOverdueIDs.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(recentLimit)

        return DashboardSnapshot(
            metrics: metrics,
            dueToday: dueToday,
            overdue: Array(overdueAll.prefix(overduePreviewLimit)),
            overdueTotalCount: overdueAll.count,
            recentlyUpdated: Array(recentlyUpdated),
            activeProjects: Array(activeProjects.prefix(activeProjectsLimit)),
            activeProjectTotalCount: activeProjects.count
        )
    }

    private static func dueTodaySort(_ lhs: DashboardTaskInput, _ rhs: DashboardTaskInput) -> Bool {
        if lhs.priority.sortRank != rhs.priority.sortRank {
            return lhs.priority.sortRank > rhs.priority.sortRank
        }
        let lhsDue = lhs.dueDate ?? .distantFuture
        let rhsDue = rhs.dueDate ?? .distantFuture
        if lhsDue != rhsDue { return lhsDue < rhsDue }
        return lhs.position < rhs.position
    }

    private static func overdueSort(_ lhs: DashboardTaskInput, _ rhs: DashboardTaskInput) -> Bool {
        let lhsDue = lhs.dueDate ?? .distantPast
        let rhsDue = rhs.dueDate ?? .distantPast
        if lhsDue != rhsDue { return lhsDue < rhsDue }
        return lhs.priority.sortRank > rhs.priority.sortRank
    }
}

public extension TaskPriority {
    /// Higher is more important.
    var sortRank: Int {
        switch self {
        case .urgent: return 4
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .none: return 0
        }
    }
}
