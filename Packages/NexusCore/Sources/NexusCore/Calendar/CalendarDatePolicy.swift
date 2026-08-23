import Foundation

/// Pure calendar day/week/month arithmetic. Always inject `Calendar` in tests.
public enum CalendarDatePolicy: Sendable {
    public static func startOfDay(
        _ date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func isSameDay(
        _ lhs: Date?,
        _ rhs: Date?,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard let lhs, let rhs else { return false }
        return calendar.isDate(lhs, inSameDayAs: rhs)
    }

    public static func isToday(
        _ date: Date,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        calendar.isDate(date, inSameDayAs: now)
    }

    /// Exclusive end (start of next day).
    public static func endOfDayExclusive(
        _ date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start
    }

    public static func startOfWeek(
        containing date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let day = calendar.startOfDay(for: date)
        if let interval = calendar.dateInterval(of: .weekOfYear, for: day) {
            return interval.start
        }
        // Fallback: walk back to firstWeekday.
        var cursor = day
        let first = calendar.firstWeekday
        for _ in 0..<7 {
            if calendar.component(.weekday, from: cursor) == first {
                return cursor
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return day
    }

    public static func endOfWeekExclusive(
        containing date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let start = startOfWeek(containing: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: 7, to: start) ?? start
    }

    /// Seven start-of-day dates beginning at the week that contains `date`.
    public static func weekDays(
        containing date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Date] {
        let start = startOfWeek(containing: date, calendar: calendar)
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
    }

    public static func startOfMonth(
        containing date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let day = calendar.startOfDay(for: date)
        let comps = calendar.dateComponents([.year, .month], from: day)
        return calendar.date(from: comps) ?? day
    }

    public static func endOfMonthExclusive(
        containing date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let start = startOfMonth(containing: date, calendar: calendar)
        return calendar.date(byAdding: .month, value: 1, to: start) ?? start
    }

    public static func nextMonth(
        after date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let start = startOfMonth(containing: date, calendar: calendar)
        return calendar.date(byAdding: .month, value: 1, to: start) ?? date
    }

    public static func previousMonth(
        before date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let start = startOfMonth(containing: date, calendar: calendar)
        return calendar.date(byAdding: .month, value: -1, to: start) ?? date
    }

    public static func nextWeek(
        after date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: date)) ?? date
    }

    public static func previousWeek(
        before date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: date)) ?? date
    }

    public static func tomorrow(
        relativeTo now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// Month grid with leading padding for firstWeekday alignment. Always 6×7 = 42 cells.
    /// Leading/trailing out-of-month dates are included (not blanks) for a continuous grid.
    public static func monthGridDates(
        containing date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Date] {
        let monthStart = startOfMonth(containing: date, calendar: calendar)
        let gridStart = startOfWeek(containing: monthStart, calendar: calendar)
        return (0..<42).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: gridStart)
        }
    }

    public static func isInSameMonth(
        _ date: Date,
        as reference: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        calendar.isDate(date, equalTo: reference, toGranularity: .month)
    }

    public static func dueOnDay(
        _ dueDate: Date?,
        day: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard let dueDate else { return false }
        return calendar.isDate(dueDate, inSameDayAs: day)
    }

    /// Days until next local midnight after `now`, at least 1 second.
    public static func secondsUntilNextMidnight(
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> TimeInterval {
        let start = calendar.startOfDay(for: now)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)
        return max(1, next.timeIntervalSince(now))
    }
}
