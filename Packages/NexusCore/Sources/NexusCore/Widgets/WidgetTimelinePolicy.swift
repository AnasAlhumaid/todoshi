import Foundation

/// Timeline planning for widget reload dates (testable pure logic).
public enum WidgetTimelinePolicy: Sendable {
    /// Default fallback when no nearer boundary applies (6 hours).
    public static let fallbackInterval: TimeInterval = 6 * 60 * 60

    public static func nextRefreshDate(
        after now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        dueDates: [Date] = [],
        fallbackInterval: TimeInterval = fallbackInterval
    ) -> Date {
        let startOfTomorrow: Date = {
            let startToday = calendar.startOfDay(for: now)
            return calendar.date(byAdding: .day, value: 1, to: startToday) ?? now.addingTimeInterval(86_400)
        }()

        var candidates: [Date] = [startOfTomorrow, now.addingTimeInterval(fallbackInterval)]

        for due in dueDates {
            if due > now {
                candidates.append(due)
            }
            // Also refresh shortly after midnight preceding a due date day (start of due day)
            let startDueDay = calendar.startOfDay(for: due)
            if startDueDay > now {
                candidates.append(startDueDay)
            }
        }

        let future = candidates.filter { $0 > now }.sorted()
        return future.first ?? now.addingTimeInterval(fallbackInterval)
    }

    public static func isValidFutureRefresh(_ date: Date, now: Date) -> Bool {
        date > now
    }
}
