import Foundation

/// Aggregates for dashboard productivity sections. Uses `completedAt`, never `updatedAt`.
public enum ProductivityMetrics: Sendable {
    public struct Snapshot: Equatable, Sendable {
        public var completedToday: Int
        public var completedThisWeek: Int
        public var openRootTasks: Int
        public var overdueRootTasks: Int

        public init(
            completedToday: Int = 0,
            completedThisWeek: Int = 0,
            openRootTasks: Int = 0,
            overdueRootTasks: Int = 0
        ) {
            self.completedToday = completedToday
            self.completedThisWeek = completedThisWeek
            self.openRootTasks = openRootTasks
            self.overdueRootTasks = overdueRootTasks
        }
    }

    public static func completedCount(
        completedAtValues: [Date?],
        in interval: DateInterval
    ) -> Int {
        completedAtValues.reduce(into: 0) { count, completedAt in
            if TaskPredicates.isCompleted(completedAt, in: interval) {
                count += 1
            }
        }
    }

    public static func openCount(statuses: [TaskStatus]) -> Int {
        statuses.filter { $0 != .done }.count
    }

    /// Metrics over root tasks that already belong to active projects only.
    public static func snapshot(
        rootTasks: [DashboardTaskInput],
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> Snapshot {
        let today = TaskPredicates.todayInterval(calendar: calendar, now: now)
        let week = TaskPredicates.currentWeekInterval(calendar: calendar, now: now)

        var completedToday = 0
        var completedThisWeek = 0
        var open = 0
        var overdue = 0

        for task in rootTasks {
            if TaskPredicates.isCompleted(task.completedAt, in: today) {
                completedToday += 1
            }
            if TaskPredicates.isCompleted(task.completedAt, in: week) {
                completedThisWeek += 1
            }
            if task.status != .done {
                open += 1
                if TaskPredicates.isOverdue(task.dueDate, status: task.status, calendar: calendar, now: now) {
                    overdue += 1
                }
            }
        }

        return Snapshot(
            completedToday: completedToday,
            completedThisWeek: completedThisWeek,
            openRootTasks: open,
            overdueRootTasks: overdue
        )
    }
}
