import Foundation

/// Pure calendar/domain helpers for task filtering (no SwiftData dependency).
public enum TaskPredicates: Sendable {
    public static func isDueToday(
        _ dueDate: Date?,
        status: TaskStatus,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> Bool {
        guard let dueDate, status != .done else { return false }
        return calendar.isDate(dueDate, inSameDayAs: now)
    }

    /// Open task with due date strictly before start of `now`'s calendar day.
    public static func isOverdue(
        _ dueDate: Date?,
        status: TaskStatus,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> Bool {
        guard let dueDate, status != .done else { return false }
        let startOfToday = calendar.startOfDay(for: now)
        return dueDate < startOfToday
    }

    public static func isCompleted(
        _ completedAt: Date?,
        in interval: DateInterval
    ) -> Bool {
        guard let completedAt else { return false }
        return interval.contains(completedAt)
    }

    public static func isCompletedToday(
        _ completedAt: Date?,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> Bool {
        guard let completedAt else { return false }
        return calendar.isDate(completedAt, inSameDayAs: now)
    }

    public static func isCompletedThisWeek(
        _ completedAt: Date?,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> Bool {
        guard let completedAt,
              let interval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return false
        }
        return interval.contains(completedAt)
    }

    /// Whole days from due calendar day to `now` calendar day (0 if due today or later).
    public static func overdueDayCount(
        dueDate: Date,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> Int {
        let startDue = calendar.startOfDay(for: dueDate)
        let startNow = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: startDue, to: startNow).day ?? 0)
    }

    public static func todayInterval(
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    public static func currentWeekInterval(
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: now)
            ?? todayInterval(calendar: calendar, now: now)
    }
}
