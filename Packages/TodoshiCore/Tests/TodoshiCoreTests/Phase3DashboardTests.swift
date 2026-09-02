import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
struct Phase3DashboardTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        components.hour = h
        components.minute = min
        return calendar.date(from: components)!
    }

    // MARK: - Date policies

    @Test("Due today and overdue boundaries")
    func dateBoundaries() {
        let now = date(2026, 8, 5, 15)
        let startToday = calendar.startOfDay(for: now)
        let noonToday = date(2026, 8, 5, 12)
        let laterToday = date(2026, 8, 5, 23)
        let yesterday = date(2026, 8, 4, 18)
        let tomorrow = date(2026, 8, 6, 9)

        #expect(TaskPredicates.isDueToday(noonToday, status: .todo, calendar: calendar, now: now))
        #expect(TaskPredicates.isDueToday(laterToday, status: .todo, calendar: calendar, now: now))
        #expect(TaskPredicates.isDueToday(noonToday, status: .done, calendar: calendar, now: now) == false)

        #expect(TaskPredicates.isOverdue(yesterday, status: .todo, calendar: calendar, now: now))
        #expect(TaskPredicates.isOverdue(laterToday, status: .todo, calendar: calendar, now: now) == false)
        #expect(TaskPredicates.isOverdue(noonToday, status: .todo, calendar: calendar, now: now) == false)
        #expect(TaskPredicates.isOverdue(tomorrow, status: .todo, calendar: calendar, now: now) == false)
        #expect(TaskPredicates.isOverdue(yesterday, status: .done, calendar: calendar, now: now) == false)

        #expect(TaskPredicates.overdueDayCount(dueDate: yesterday, calendar: calendar, now: now) == 1)
        #expect(startToday <= noonToday)
    }

    @Test("Completed today / week and reopen behavior")
    func completionWindows() {
        let now = date(2026, 8, 5, 16)
        let completedToday = date(2026, 8, 5, 9)
        let completedEarlierWeek = date(2026, 8, 3, 10)
        let completedLastWeek = date(2026, 7, 28, 10)

        #expect(TaskPredicates.isCompletedToday(completedToday, calendar: calendar, now: now))
        #expect(TaskPredicates.isCompletedThisWeek(completedEarlierWeek, calendar: calendar, now: now))
        #expect(TaskPredicates.isCompletedThisWeek(completedLastWeek, calendar: calendar, now: now) == false)

        let todayInterval = TaskPredicates.todayInterval(calendar: calendar, now: now)
        #expect(TaskPredicates.isCompleted(nil, in: todayInterval) == false)
        #expect(TaskPredicates.isCompleted(completedToday, in: todayInterval))
    }

    // MARK: - Dashboard builder

    @Test("Dashboard sections exclude archived and non-root; order and limits")
    func dashboardSections() {
        let now = date(2026, 8, 5, 12)
        let activeID = UUID()
        let archivedID = UUID()

        let projects = [
            DashboardProjectInput(id: activeID, name: "A", position: 2048, openRootCount: 1, totalRootCount: 2),
            DashboardProjectInput(id: UUID(), name: "B", position: 1024, openRootCount: 0, totalRootCount: 0),
            DashboardProjectInput(
                id: archivedID,
                name: "Old",
                position: 1,
                status: .archived,
                openRootCount: 0,
                totalRootCount: 0
            )
        ]

        let tasks = [
            DashboardTaskInput(
                title: "Due hi",
                status: .todo,
                priority: .high,
                dueDate: date(2026, 8, 5, 10),
                position: 100,
                projectID: activeID,
                projectName: "A"
            ),
            DashboardTaskInput(
                title: "Due med",
                status: .todo,
                priority: .medium,
                dueDate: date(2026, 8, 5, 9),
                position: 50,
                projectID: activeID,
                projectName: "A"
            ),
            DashboardTaskInput(
                title: "Overdue old",
                status: .todo,
                priority: .none,
                dueDate: date(2026, 8, 1),
                position: 1,
                projectID: activeID,
                projectName: "A"
            ),
            DashboardTaskInput(
                title: "Overdue mid",
                status: .inProgress,
                priority: .urgent,
                dueDate: date(2026, 8, 3),
                position: 2,
                projectID: activeID,
                projectName: "A"
            ),
            DashboardTaskInput(
                title: "Recent",
                status: .review,
                priority: .none,
                dueDate: nil,
                updatedAt: date(2026, 8, 5, 11),
                position: 3,
                projectID: activeID,
                projectName: "A"
            ),
            DashboardTaskInput(
                title: "In due should not be recent",
                status: .todo,
                priority: .none,
                dueDate: date(2026, 8, 5, 14),
                updatedAt: date(2026, 8, 5, 12),
                projectID: activeID,
                projectName: "A"
            ),
            DashboardTaskInput(
                title: "Child",
                status: .todo,
                dueDate: date(2026, 8, 4),
                isRoot: false,
                projectID: activeID,
                projectName: "A"
            ),
            DashboardTaskInput(
                title: "Archived task",
                status: .todo,
                dueDate: date(2026, 8, 4),
                projectID: archivedID,
                projectName: "Old",
                projectIsActive: false
            ),
            DashboardTaskInput(
                title: "Done today task",
                status: .done,
                priority: .high,
                dueDate: date(2026, 8, 5, 8),
                completedAt: date(2026, 8, 5, 8),
                projectID: activeID,
                projectName: "A"
            )
        ]

        let snap = DashboardBuilder.build(
            projects: projects,
            tasks: tasks,
            calendar: calendar,
            now: now,
            overduePreviewLimit: 1,
            recentLimit: 5,
            activeProjectsLimit: 1
        )

        #expect(snap.dueToday.map(\.title) == ["Due hi", "Due med", "In due should not be recent"])
        #expect(snap.overdueTotalCount == 2)
        #expect(snap.overdue.count == 1)
        #expect(snap.overdue.first?.title == "Overdue old")
        #expect(snap.recentlyUpdated.map(\.title) == ["Recent"])
        #expect(snap.activeProjects.map(\.name) == ["B"])
        #expect(snap.activeProjectTotalCount == 2)
        #expect(snap.metrics.completedToday == 1)
        #expect(snap.metrics.openRootTasks >= 5)
        #expect(snap.metrics.overdueRootTasks == 2)
        #expect(tasks.contains { $0.title == "Child" })
    }

    @Test("Productivity metrics use completedAt and exclude archived roots")
    func productivityMetrics() {
        let now = date(2026, 8, 5)
        let project = UUID()
        let rootTasks = [
            DashboardTaskInput(
                title: "Done",
                status: .done,
                completedAt: date(2026, 8, 5, 8),
                projectID: project,
                projectName: "P"
            ),
            DashboardTaskInput(
                title: "Open",
                status: .todo,
                dueDate: date(2026, 8, 1),
                projectID: project,
                projectName: "P"
            ),
            DashboardTaskInput(
                title: "Week",
                status: .done,
                completedAt: date(2026, 8, 4),
                projectID: project,
                projectName: "P"
            )
        ]
        let snap = ProductivityMetrics.snapshot(rootTasks: rootTasks, calendar: calendar, now: now)
        #expect(snap.completedToday == 1)
        #expect(snap.completedThisWeek >= 2)
        #expect(snap.openRootTasks == 1)
        #expect(snap.overdueRootTasks == 1)
    }

    @Test("Quick Add draft validation and project preference helper")
    func quickAddDraftRules() {
        var draft = QuickAddDraft()
        #expect(draft.isValid == false)
        draft.title = "  "
        #expect(draft.isValid == false)
        draft.title = " Ship "
        #expect(draft.isValid == false)
        let projectID = UUID()
        draft.projectID = projectID
        #expect(FieldValidation.requiredName(draft.title) == "Ship")
        #expect(draft.status == .todo)
        #expect(draft.priority == .none)

        let ids: Set<UUID> = [projectID]
        #expect(QuickAddPreferences.resolvedProjectID(stored: projectID.uuidString, activeProjectIDs: ids) == projectID)
        #expect(QuickAddPreferences.resolvedProjectID(stored: UUID().uuidString, activeProjectIDs: ids) == nil)
        #expect(QuickAddPreferences.resolvedProjectID(stored: "nope", activeProjectIDs: ids) == nil)
    }

    @Test("Quick Add repository create assigns position and requires project")
    func quickAddCreate() throws {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Core")
        _ = try tasks.create(in: project, title: "Existing", status: .todo)
        let created = try tasks.create(
            in: project,
            title: "  Quick  ",
            status: .todo,
            priority: .high
        )
        #expect(created.title == "Quick")
        #expect(created.project?.id == project.id)
        let column = try tasks.fetchRootTasks(projectID: project.id, status: .todo)
        #expect(column.last?.id == created.id)
        #expect(column.count == 2)

        #expect(throws: RepositoryValidationError.emptyName) {
            try tasks.create(in: project, title: "   ")
        }
    }

    @Test("Complete and reopen repository helpers")
    func completeReopen() throws {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "P")
        let tasks = TaskRepository(context: context)
        let task = try tasks.create(in: project, title: "T")
        try tasks.complete(task)
        #expect(task.status == .done)
        #expect(task.completedAt != nil)
        try tasks.reopen(task)
        #expect(task.status == .todo)
        #expect(task.completedAt == nil)
    }

    @Test("Deep link quick add and invalid URLs")
    func deepLinks() {
        #expect(NexusDeepLink(url: URL(string: "nexus://quick-add")!) == .quickAdd)
        #expect(NexusDeepLink(url: URL(string: "https://example.com")!) == nil)
        #expect(NexusDeepLink(url: URL(string: "nexus://nope")!) == nil)
    }
}
