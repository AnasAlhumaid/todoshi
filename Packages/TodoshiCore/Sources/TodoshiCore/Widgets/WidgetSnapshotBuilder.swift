import Foundation

/// Pure selection/ranking helpers for widget task lists.
public enum WidgetSnapshotBuilder: Sendable {
    public static let defaultTodayLimit = 6
    public static let defaultPriorityLimit = 6
    /// Max tasks embedded in a project snapshot payload (UI may show fewer per family).
    /// `totalCount` always reflects the full filtered set before this display cap.
    public static let defaultProjectLimit = 6
    public static let projectFamilyLimitSmall = 1
    public static let projectFamilyLimitMedium = 3
    public static let projectFamilyLimitLarge = 6

    /// Open workflow statuses shown in Project Tasks (excludes `.done`).
    private static let projectStatusOrder: [TaskStatus: Int] = [
        .inProgress: 0,
        .review: 1,
        .todo: 2,
        .backlog: 3
    ]

    public static func mapItem(
        id: UUID,
        title: String,
        projectID: UUID,
        projectName: String,
        projectIcon: String,
        projectColorHex: String,
        status: TaskStatus,
        priority: TaskPriority,
        dueDate: Date?,
        calendar: Calendar,
        now: Date
    ) -> WidgetTaskItem {
        WidgetTaskItem(
            id: id,
            title: title,
            projectID: projectID,
            projectName: projectName,
            projectIcon: projectIcon,
            projectColorHex: projectColorHex,
            status: status,
            priority: priority,
            dueDate: dueDate,
            isOverdue: TaskPredicates.isOverdue(dueDate, status: status, calendar: calendar, now: now)
        )
    }

    public static func todaySnapshot(
        tasks: [DashboardTaskInput],
        limit: Int = defaultTodayLimit,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> WidgetTaskSnapshot {
        let selected = tasks
            .filter { $0.isRoot && $0.projectIsActive && $0.status != .done }
            .filter { TaskPredicates.isDueToday($0.dueDate, status: $0.status, calendar: calendar, now: now) }
            .sorted(by: todaySort)
        let items = selected.prefix(limit).map { mapDashboard($0, calendar: calendar, now: now) }
        return WidgetTaskSnapshot(
            generatedAt: now,
            title: NexusL10n.tr("widget.today"),
            tasks: Array(items),
            totalCount: selected.count
        )
    }

    public static func highPrioritySnapshot(
        tasks: [DashboardTaskInput],
        limit: Int = defaultPriorityLimit,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> WidgetTaskSnapshot {
        let selected = tasks
            .filter { $0.isRoot && $0.projectIsActive && $0.status != .done }
            .filter { $0.priority == .high || $0.priority == .urgent }
            .sorted { lhs, rhs in
                if lhs.priority.sortRank != rhs.priority.sortRank {
                    return lhs.priority.sortRank > rhs.priority.sortRank
                }
                let lhsOverdue = TaskPredicates.isOverdue(lhs.dueDate, status: lhs.status, calendar: calendar, now: now)
                let rhsOverdue = TaskPredicates.isOverdue(rhs.dueDate, status: rhs.status, calendar: calendar, now: now)
                if lhsOverdue != rhsOverdue { return lhsOverdue && !rhsOverdue }
                switch (lhs.dueDate, rhs.dueDate) {
                case let (l?, r?):
                    if l != r { return l < r }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
                return lhs.updatedAt > rhs.updatedAt
            }
        let items = selected.prefix(limit).map { mapDashboard($0, calendar: calendar, now: now) }
        return WidgetTaskSnapshot(
            generatedAt: now,
            title: NexusL10n.tr("widget.highPriority"),
            tasks: Array(items),
            totalCount: selected.count
        )
    }

    public static func projectSnapshot(
        projectID: UUID?,
        projectName: String?,
        projectIcon: String?,
        projectColorHex: String?,
        projectIsActive: Bool?,
        tasks: [DashboardTaskInput],
        limit: Int = defaultProjectLimit,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> WidgetTaskSnapshot {
        guard let projectID else {
            return .needsConfiguration(generatedAt: now)
        }
        guard projectIsActive == true, let projectName else {
            return WidgetTaskSnapshot(
                generatedAt: now,
                title: projectName ?? NexusL10n.tr("common.project"),
                tasks: [],
                totalCount: 0,
                projectID: projectID,
                projectIcon: projectIcon,
                projectColorHex: projectColorHex,
                projectAvailability: .unavailable
            )
        }

        // Open root tasks only for this active project — no due-date filter.
        let selected = tasks
            .filter { task in
                task.isRoot
                    && task.projectID == projectID
                    && task.projectIsActive
                    && projectStatusOrder[task.status] != nil
            }
            .sorted(by: projectSort)
        let items = selected.prefix(limit).map { mapDashboard($0, calendar: calendar, now: now) }
        return WidgetTaskSnapshot(
            generatedAt: now,
            title: projectName,
            tasks: Array(items),
            totalCount: selected.count,
            projectID: projectID,
            projectIcon: projectIcon,
            projectColorHex: projectColorHex,
            projectAvailability: .available
        )
    }

    private static func mapDashboard(
        _ task: DashboardTaskInput,
        calendar: Calendar,
        now: Date
    ) -> WidgetTaskItem {
        mapItem(
            id: task.id,
            title: task.title,
            projectID: task.projectID,
            projectName: task.projectName,
            projectIcon: task.projectIcon,
            projectColorHex: task.projectColorHex,
            status: task.status,
            priority: task.priority,
            dueDate: task.dueDate,
            calendar: calendar,
            now: now
        )
    }

    private static func todaySort(_ lhs: DashboardTaskInput, _ rhs: DashboardTaskInput) -> Bool {
        if lhs.priority.sortRank != rhs.priority.sortRank {
            return lhs.priority.sortRank > rhs.priority.sortRank
        }
        let lhsDue = lhs.dueDate ?? .distantFuture
        let rhsDue = rhs.dueDate ?? .distantFuture
        if lhsDue != rhsDue { return lhsDue < rhsDue }
        return lhs.position < rhs.position
    }

    /// Status order → position → priority desc → updatedAt desc.
    private static func projectSort(_ lhs: DashboardTaskInput, _ rhs: DashboardTaskInput) -> Bool {
        let lo = projectStatusOrder[lhs.status] ?? 99
        let ro = projectStatusOrder[rhs.status] ?? 99
        if lo != ro { return lo < ro }
        if lhs.position != rhs.position { return lhs.position < rhs.position }
        if lhs.priority.sortRank != rhs.priority.sortRank {
            return lhs.priority.sortRank > rhs.priority.sortRank
        }
        return lhs.updatedAt > rhs.updatedAt
    }
}
