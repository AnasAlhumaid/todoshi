import Foundation

/// Pure calendar schedule construction from mapped task values.
///
/// Presentation notes:
/// - Due dates are absolute timestamps; Nexus has no all-day flag, so Day agenda lists
///   all due tasks ordered by due time (no invented “Any Time” group).
/// - Agenda shows open tasks by default; completed due that day appear when `includeCompleted`.
/// - Day/week/month count chips include open + completed due that day.
/// - Overdue section only when selected day is today.
/// - Subtasks never appear as independent calendar rows.
public enum CalendarScheduleBuilder: Sendable {
    // MARK: Eligibility

    public static func eligibleRoots(_ tasks: [CalendarTaskSource]) -> [CalendarTaskSource] {
        tasks.filter { $0.isRoot && $0.projectIsActive }
    }

    // MARK: Presentation mapping

    public static func present(
        _ source: CalendarTaskSource,
        now: Date,
        calendar: Calendar
    ) -> CalendarTaskItem? {
        guard let due = source.dueDate else { return nil }
        let isOverdue = TaskPredicates.isOverdue(
            due,
            status: source.status,
            calendar: calendar,
            now: now
        )
        return CalendarTaskItem(
            id: source.id,
            title: source.title,
            projectID: source.projectID,
            projectName: source.projectName,
            projectIcon: source.projectIcon,
            projectColorHex: source.projectColorHex,
            dueDate: due,
            status: source.status,
            priority: source.priority,
            position: source.position,
            updatedAt: source.updatedAt,
            isOverdue: isOverdue,
            isRecurring: source.isRecurring,
            checklistProgress: source.checklistProgress,
            subtaskProgress: source.subtaskProgress
        )
    }

    // MARK: Day

    public static func dayAgenda(
        tasks: [CalendarTaskSource],
        selectedDay: Date,
        includeCompleted: Bool = false,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> CalendarDayAgenda {
        let roots = eligibleRoots(tasks)
        let dayStart = calendar.startOfDay(for: selectedDay)
        let isSelectedToday = calendar.isDate(dayStart, inSameDayAs: now)

        let dueOnDaySources = roots.filter { source in
            guard CalendarDatePolicy.dueOnDay(source.dueDate, day: dayStart, calendar: calendar) else {
                return false
            }
            if source.status == .done {
                return includeCompleted
            }
            return true
        }

        let dueOnDay = dueOnDaySources
            .compactMap { present($0, now: now, calendar: calendar) }
            .sorted(by: agendaSort)

        var overdueWhenToday: [CalendarTaskItem] = []
        if isSelectedToday {
            let dueIDs = Set(dueOnDay.map(\.id))
            overdueWhenToday = roots
                .filter {
                    TaskPredicates.isOverdue($0.dueDate, status: $0.status, calendar: calendar, now: now)
                        && !dueIDs.contains($0.id)
                }
                .compactMap { present($0, now: now, calendar: calendar) }
                .sorted(by: overdueSort)
        }

        return CalendarDayAgenda(dueOnDay: dueOnDay, overdueWhenToday: overdueWhenToday)
    }

    // MARK: Week

    public static func weekSummaries(
        containing selectedDay: Date,
        tasks: [CalendarTaskSource],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [CalendarDaySummary] {
        let days = CalendarDatePolicy.weekDays(containing: selectedDay, calendar: calendar)
        return days.map { daySummary(for: $0, tasks: tasks, now: now, calendar: calendar) }
    }

    public static func daySummary(
        for day: Date,
        tasks: [CalendarTaskSource],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> CalendarDaySummary {
        let roots = eligibleRoots(tasks)
        let dayStart = calendar.startOfDay(for: day)
        let dueThatDay = roots.filter {
            CalendarDatePolicy.dueOnDay($0.dueDate, day: dayStart, calendar: calendar)
        }
        let openCount = dueThatDay.filter { $0.status != .done }.count
        let completedCount = dueThatDay.filter { $0.status == .done }.count
        let overdueOpenCount = dueThatDay.filter {
            $0.status != .done
                && TaskPredicates.isOverdue($0.dueDate, status: $0.status, calendar: calendar, now: now)
        }.count
        return CalendarDaySummary(
            date: dayStart,
            openCount: openCount,
            completedCount: completedCount,
            overdueOpenCount: overdueOpenCount
        )
    }

    // MARK: Month

    public static func monthCells(
        containing monthDate: Date,
        tasks: [CalendarTaskSource],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [CalendarMonthCell] {
        let grid = CalendarDatePolicy.monthGridDates(containing: monthDate, calendar: calendar)
        return grid.map { date in
            let inMonth = CalendarDatePolicy.isInSameMonth(date, as: monthDate, calendar: calendar)
            let summary = daySummary(for: date, tasks: tasks, now: now, calendar: calendar)
            return CalendarMonthCell(
                date: date,
                dayNumber: calendar.component(.day, from: date),
                isInMonth: inMonth,
                summary: summary
            )
        }
    }

    // MARK: Upcoming

    /// Open root tasks due **strictly after today**. Groups are exclusive:
    /// Tomorrow → rest of this week (after tomorrow) → next week → later.
    public static func upcoming(
        tasks: [CalendarTaskSource],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [UpcomingGroup] {
        let roots = eligibleRoots(tasks)
        let tomorrowStart = CalendarDatePolicy.tomorrow(relativeTo: now, calendar: calendar)
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 1, to: tomorrowStart) ?? tomorrowStart
        let thisWeekEnd = CalendarDatePolicy.endOfWeekExclusive(containing: now, calendar: calendar)
        let nextWeekStart = thisWeekEnd
        let nextWeekEnd = calendar.date(byAdding: .day, value: 7, to: nextWeekStart) ?? nextWeekStart

        let candidates = roots.filter { source in
            guard source.status != .done, let due = source.dueDate else { return false }
            let day = calendar.startOfDay(for: due)
            return day >= tomorrowStart
        }

        var tomorrowItems: [CalendarTaskItem] = []
        var thisWeekItems: [CalendarTaskItem] = []
        var nextWeekItems: [CalendarTaskItem] = []
        var laterItems: [CalendarTaskItem] = []

        for source in candidates {
            guard let due = source.dueDate,
                  let item = present(source, now: now, calendar: calendar) else { continue }
            let day = calendar.startOfDay(for: due)
            if day == tomorrowStart {
                tomorrowItems.append(item)
            } else if day >= dayAfterTomorrow && day < thisWeekEnd {
                thisWeekItems.append(item)
            } else if day >= nextWeekStart && day < nextWeekEnd {
                nextWeekItems.append(item)
            } else if day >= nextWeekEnd {
                laterItems.append(item)
            }
            // If tomorrow is after thisWeekEnd (shouldn't happen for normal weeks), fall through unused.
        }

        tomorrowItems.sort(by: upcomingSort)
        thisWeekItems.sort(by: upcomingSort)
        nextWeekItems.sort(by: upcomingSort)
        laterItems.sort(by: upcomingSort)

        return [
            UpcomingGroup(kind: .tomorrow, tasks: tomorrowItems),
            UpcomingGroup(kind: .thisWeek, tasks: thisWeekItems),
            UpcomingGroup(kind: .nextWeek, tasks: nextWeekItems),
            UpcomingGroup(kind: .later, tasks: laterItems)
        ].filter { !$0.tasks.isEmpty }
    }

    // MARK: Unscheduled

    /// Open root tasks with no due date (active projects only).
    public static func unscheduledSources(
        tasks: [CalendarTaskSource]
    ) -> [CalendarTaskSource] {
        eligibleRoots(tasks)
            .filter { $0.status != .done && $0.dueDate == nil }
            .sorted { lhs, rhs in
                if lhs.position != rhs.position { return lhs.position < rhs.position }
                if lhs.priority.sortRank != rhs.priority.sortRank {
                    return lhs.priority.sortRank > rhs.priority.sortRank
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    // MARK: Sorting

    /// 1) Due time ascending 2) Priority desc 3) Position 4) Updated
    public static func agendaSort(_ lhs: CalendarTaskItem, _ rhs: CalendarTaskItem) -> Bool {
        if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
        if lhs.priority.sortRank != rhs.priority.sortRank {
            return lhs.priority.sortRank > rhs.priority.sortRank
        }
        if lhs.position != rhs.position { return lhs.position < rhs.position }
        return lhs.updatedAt > rhs.updatedAt
    }

    private static func overdueSort(_ lhs: CalendarTaskItem, _ rhs: CalendarTaskItem) -> Bool {
        if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
        if lhs.priority.sortRank != rhs.priority.sortRank {
            return lhs.priority.sortRank > rhs.priority.sortRank
        }
        return lhs.position < rhs.position
    }

    private static func upcomingSort(_ lhs: CalendarTaskItem, _ rhs: CalendarTaskItem) -> Bool {
        if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
        if lhs.priority.sortRank != rhs.priority.sortRank {
            return lhs.priority.sortRank > rhs.priority.sortRank
        }
        if lhs.position != rhs.position { return lhs.position < rhs.position }
        return lhs.updatedAt > rhs.updatedAt
    }
}
