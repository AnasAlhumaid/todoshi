import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
struct Phase12CalendarTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.firstWeekday = 2 // Monday
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        return calendar.date(from: c)!
    }

    private func source(
        id: UUID = UUID(),
        title: String,
        due: Date?,
        status: TaskStatus = .todo,
        priority: TaskPriority = .none,
        position: Double = 1,
        isRoot: Bool = true,
        active: Bool = true,
        projectID: UUID = UUID(),
        recurring: Bool = false,
        updatedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> CalendarTaskSource {
        CalendarTaskSource(
            id: id,
            title: title,
            status: status,
            priority: priority,
            dueDate: due,
            updatedAt: updatedAt,
            position: position,
            isRoot: isRoot,
            isRecurring: recurring,
            projectID: projectID,
            projectName: "P",
            projectIsActive: active
        )
    }

    // MARK: Date policy

    @Test("Same-day, week start Monday/Sunday, month and leap February")
    func datePolicies() {
        let mon = date(2026, 8, 10) // Monday
        #expect(CalendarDatePolicy.isSameDay(mon, date(2026, 8, 10, 23), calendar: calendar))

        let week = CalendarDatePolicy.weekDays(containing: mon, calendar: calendar)
        #expect(week.count == 7)
        #expect(calendar.component(.weekday, from: week[0]) == 2)
        #expect(calendar.isDate(week[0], inSameDayAs: date(2026, 8, 10)))
        #expect(calendar.isDate(week[6], inSameDayAs: date(2026, 8, 16)))

        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        let sunWeek = CalendarDatePolicy.weekDays(containing: mon, calendar: sundayFirst)
        #expect(sundayFirst.component(.weekday, from: sunWeek[0]) == 1)
        #expect(sundayFirst.isDate(sunWeek[0], inSameDayAs: date(2026, 8, 9)))

        let feb2024 = date(2024, 2, 15)
        let end = CalendarDatePolicy.endOfMonthExclusive(containing: feb2024, calendar: calendar)
        #expect(calendar.isDate(end, inSameDayAs: date(2024, 3, 1)))

        let grid = CalendarDatePolicy.monthGridDates(containing: date(2026, 2, 1), calendar: calendar)
        #expect(grid.count == 42)

        let tomorrow = CalendarDatePolicy.tomorrow(relativeTo: date(2026, 8, 10, 15), calendar: calendar)
        #expect(calendar.isDate(tomorrow, inSameDayAs: date(2026, 8, 11)))

        #expect(CalendarDatePolicy.secondsUntilNextMidnight(now: date(2026, 8, 10, 23, 30), calendar: calendar) > 0)
    }

    // MARK: Day agenda

    @Test("Day agenda filters, ordering, overdue only today, no duplicates")
    func dayAgenda() {
        let today = date(2026, 8, 10, 12)
        let project = UUID()
        let a = source(title: "Later", due: date(2026, 8, 10, 17), priority: .low, position: 2, projectID: project)
        let b = source(title: "Earlier high", due: date(2026, 8, 10, 9), priority: .high, position: 1, projectID: project)
        let c = source(title: "Other day", due: date(2026, 8, 11, 9), projectID: project)
        let overdue = source(title: "Old", due: date(2026, 8, 8, 9), projectID: project)
        let done = source(title: "Done", due: date(2026, 8, 10, 10), status: .done, projectID: project)
        let archived = source(title: "Arch", due: date(2026, 8, 10, 8), active: false, projectID: UUID())
        let child = source(title: "Sub", due: date(2026, 8, 10, 8), isRoot: false, projectID: project)

        let agenda = CalendarScheduleBuilder.dayAgenda(
            tasks: [a, b, c, overdue, done, archived, child],
            selectedDay: today,
            includeCompleted: false,
            now: today,
            calendar: calendar
        )
        #expect(agenda.dueOnDay.map(\.title) == ["Earlier high", "Later"])
        #expect(agenda.overdueWhenToday.map(\.title) == ["Old"])
        #expect(Set(agenda.dueOnDay.map(\.id)).isDisjoint(with: Set(agenda.overdueWhenToday.map(\.id))))

        let past = CalendarScheduleBuilder.dayAgenda(
            tasks: [overdue, a],
            selectedDay: date(2026, 8, 8),
            includeCompleted: false,
            now: today,
            calendar: calendar
        )
        #expect(past.overdueWhenToday.isEmpty)
        #expect(past.dueOnDay.map(\.title) == ["Old"])
        #expect(past.dueOnDay.first?.isOverdue == true)

        let future = CalendarScheduleBuilder.dayAgenda(
            tasks: [c, overdue],
            selectedDay: date(2026, 8, 11),
            now: today,
            calendar: calendar
        )
        #expect(future.overdueWhenToday.isEmpty)
        #expect(future.dueOnDay.map(\.title) == ["Other day"])

        let withDone = CalendarScheduleBuilder.dayAgenda(
            tasks: [done, b],
            selectedDay: today,
            includeCompleted: true,
            now: today,
            calendar: calendar
        )
        #expect(withDone.dueOnDay.count == 2)
    }

    // MARK: Week / Month

    @Test("Week summaries and month cells")
    func weekAndMonth() {
        let today = date(2026, 8, 12) // Wed
        let tasks = [
            source(title: "Mon", due: date(2026, 8, 10), projectID: UUID()),
            source(title: "Mon done", due: date(2026, 8, 10), status: .done, projectID: UUID()),
            source(title: "Wed", due: date(2026, 8, 12), projectID: UUID())
        ]
        let week = CalendarScheduleBuilder.weekSummaries(
            containing: today,
            tasks: tasks,
            now: today,
            calendar: calendar
        )
        #expect(week.count == 7)
        #expect(week[0].openCount == 1)
        #expect(week[0].completedCount == 1)
        let wed = week.first { calendar.isDate($0.date, inSameDayAs: today) }
        #expect(wed?.openCount == 1)

        let cells = CalendarScheduleBuilder.monthCells(
            containing: date(2026, 8, 1),
            tasks: tasks,
            now: today,
            calendar: calendar
        )
        #expect(cells.count == 42)
        #expect(cells.contains { $0.isInMonth && $0.dayNumber == 1 })
        #expect(cells.contains { $0.summary?.openCount == 1 && calendar.isDate($0.date!, inSameDayAs: date(2026, 8, 12)) })
    }

    // MARK: Upcoming / Unscheduled

    @Test("Upcoming groups exclusive; unscheduled roots only")
    func upcomingUnscheduled() {
        let now = date(2026, 8, 10, 12) // Mon
        // Week Mon 10 – Sun 16; next week 17–23
        let tasks = [
            source(title: "Today", due: date(2026, 8, 10, 15)),
            source(title: "Tmrw", due: date(2026, 8, 11, 9)),
            source(title: "ThisWeek", due: date(2026, 8, 14, 9)),
            source(title: "NextWeek", due: date(2026, 8, 18, 9)),
            source(title: "Later", due: date(2026, 9, 1, 9)),
            source(title: "Done future", due: date(2026, 8, 11), status: .done),
            source(title: "None", due: nil),
            source(title: "Arch none", due: nil, active: false),
            source(title: "Child none", due: nil, isRoot: false)
        ]
        let groups = CalendarScheduleBuilder.upcoming(tasks: tasks, now: now, calendar: calendar)
        let byKind = Dictionary(uniqueKeysWithValues: groups.map { ($0.kind, $0.tasks.map(\.title)) })
        #expect(byKind[.tomorrow] == ["Tmrw"])
        #expect(byKind[.thisWeek] == ["ThisWeek"])
        #expect(byKind[.nextWeek] == ["NextWeek"])
        #expect(byKind[.later] == ["Later"])
        let allIDs = groups.flatMap { $0.tasks.map(\.id) }
        #expect(allIDs.count == Set(allIDs).count)

        let unscheduled = CalendarScheduleBuilder.unscheduledSources(tasks: tasks)
        #expect(unscheduled.map(\.title) == ["None"])
    }

    // MARK: Operations

    @Test("updateDueDate preserves reminder and project; complete generates recurrence")
    func operations() throws {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Cal")
        let due = date(2026, 8, 10, 9)
        let reminder = date(2026, 8, 10, 7)
        let task = try tasks.create(
            in: project,
            title: "Schedule me",
            dueDate: due,
            reminderDate: reminder,
            recurrenceRule: TaskRecurrenceRule(kind: .daily)
        )
        let newDue = date(2026, 8, 12, 9)
        try tasks.updateDueDate(task, dueDate: newDue)
        #expect(task.dueDate == newDue)
        #expect(task.reminderDate == reminder)
        #expect(task.isRecurring)

        try tasks.complete(task, at: date(2026, 8, 12, 18))
        #expect(task.nextOccurrenceID != nil)
        let next = try tasks.fetchTask(id: task.nextOccurrenceID!)
        #expect(calendar.isDate(next!.dueDate!, inSameDayAs: date(2026, 8, 13, 9)))

        try tasks.updateDueDate(task, dueDate: nil)
        // completed historical can lose due without generation; open next still scheduled
        #expect(try tasks.fetchTask(id: next!.id)?.dueDate != nil)

        let open = try tasks.create(in: project, title: "Clear due", dueDate: date(2026, 8, 20), recurrenceRule: TaskRecurrenceRule(kind: .weekly))
        try tasks.updateDueDate(open, dueDate: nil)
        #expect(open.dueDate == nil)
        #expect(open.recurrenceRule == nil)

        let unscheduled = try tasks.create(in: project, title: "No due")
        #expect(unscheduled.dueDate == nil)
        let sources = CalendarMapping.taskSources(projects: [project])
        #expect(CalendarScheduleBuilder.unscheduledSources(tasks: sources).contains { $0.id == unscheduled.id })

        #expect(WidgetReloadClassifier.kinds(for: .taskDueDateChanged).contains(NexusWidgetKind.today))
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .taskDueDateChanged))
    }

    @Test("Schema unchanged at V4")
    func schemaUnchanged() {
        #expect(NexusSchema.currentVersion == NexusSchemaV4.versionIdentifier)
    }
}
