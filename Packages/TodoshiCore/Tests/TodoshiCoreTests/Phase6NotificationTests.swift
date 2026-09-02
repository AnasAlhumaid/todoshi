import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
struct Phase6NotificationTests {
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

    private func taskInput(
        id: UUID = UUID(),
        title: String = "Task",
        status: TaskStatus = .todo,
        due: Date? = nil,
        reminder: Date? = nil,
        isRoot: Bool = true,
        projectID: UUID? = UUID(),
        projectName: String? = "Nexus",
        projectIsActive: Bool = true
    ) -> TaskReminderInput {
        TaskReminderInput(
            id: id,
            title: title,
            status: status,
            dueDate: due,
            reminderDate: reminder,
            isRoot: isRoot,
            projectID: projectID,
            projectName: projectName,
            projectIsActive: projectIsActive
        )
    }

    // MARK: - Policy

    @Test("Future reminder on open active-project task schedules")
    func schedulesFuture() {
        let id = UUID()
        let now = date(2026, 8, 5, 12)
        let decision = TaskReminderPolicy.decision(
            for: taskInput(id: id, reminder: date(2026, 8, 5, 15)),
            now: now
        )
        guard case .schedule(let request) = decision else {
            Issue.record("Expected schedule"); return
        }
        #expect(request.taskID == id)
        #expect(request.taskTitle == "Task")
        #expect(request.projectName == "Nexus")
        #expect(request.identifier == NotificationIdentifier.taskReminder(taskID: id))
        // No notes/description fields on request
        let labels = Mirror(reflecting: request).children.compactMap(\.label)
        #expect(labels.contains("notes") == false)
        #expect(labels.contains("taskDescription") == false)
    }

    @Test("Past reminder cancels; done and archived cancel; missing cancels")
    func cancelRules() {
        let now = date(2026, 8, 5, 12)
        let past = TaskReminderPolicy.decision(
            for: taskInput(reminder: date(2026, 8, 5, 10)),
            now: now
        )
        #expect({
            if case .cancel = past { return true }
            return false
        }())

        let done = TaskReminderPolicy.decision(
            for: taskInput(status: .done, reminder: date(2026, 8, 5, 15)),
            now: now
        )
        #expect({
            if case .cancel = done { return true }
            return false
        }())

        let archived = TaskReminderPolicy.decision(
            for: taskInput(reminder: date(2026, 8, 5, 15), projectIsActive: false),
            now: now
        )
        #expect({
            if case .cancel = archived { return true }
            return false
        }())

        let missing = TaskReminderPolicy.decision(
            for: taskInput(reminder: nil),
            now: now
        )
        #expect({
            if case .cancel = missing { return true }
            return false
        }())
    }

    @Test("Subtasks may schedule when allowed; reopen with future schedules, expired cancels")
    func subtaskAndReopen() {
        let now = date(2026, 8, 5, 12)
        let sub = TaskReminderPolicy.decision(
            for: taskInput(reminder: date(2026, 8, 5, 15), isRoot: false),
            now: now
        )
        #expect({
            if case .schedule = sub { return TaskReminderPolicy.allowsSubtaskReminders }
            if case .cancel = sub { return !TaskReminderPolicy.allowsSubtaskReminders }
            return false
        }())

        let future = TaskReminderPolicy.decision(
            for: taskInput(status: .todo, reminder: date(2026, 8, 6, 9)),
            now: now
        )
        #expect({
            if case .schedule = future { return true }
            return false
        }())

        let expiredReopen = TaskReminderPolicy.decision(
            for: taskInput(status: .todo, reminder: date(2026, 8, 4, 9)),
            now: now
        )
        #expect({
            if case .cancel = expiredReopen { return true }
            return false
        }())
    }

    // MARK: - Validation & defaults

    @Test("Reminder validation and default never lands in the past")
    func validationAndDefault() {
        let now = date(2026, 8, 5, 12)
        #expect(TaskReminderValidation.issue(hasReminder: true, reminderDate: date(2026, 8, 5, 11), status: .todo, now: now) == .mustBeInFuture)
        #expect(TaskReminderValidation.issue(hasReminder: true, reminderDate: date(2026, 8, 5, 13), status: .todo, now: now) == nil)
        #expect(TaskReminderValidation.issue(hasReminder: true, reminderDate: date(2026, 8, 5, 13), status: .done, now: now) == .completedTaskCannotHaveReminder)
        #expect(TaskReminderValidation.issue(hasReminder: false, reminderDate: nil, status: .todo, now: now) == nil)

        let def = TaskReminderValidation.defaultReminderDate(dueDate: nil, now: now, calendar: calendar)
        #expect(def > now)

        let due = date(2026, 8, 5, 18)
        let beforeDue = TaskReminderValidation.defaultReminderDate(dueDate: due, now: now, calendar: calendar)
        #expect(beforeDue > now)
        #expect(beforeDue <= due)

        var draft = TaskDraft(hasReminder: true, reminderDate: date(2026, 8, 5, 14))
        draft.disableReminder()
        #expect(draft.hasReminder == false)
        #expect(draft.resolvedReminderDate == nil)
    }

    // MARK: - Reconciliation planner

    @Test("Reconcile schedules expected, cancels stale Nexus, ignores foreign")
    func reconcilePlan() {
        let now = date(2026, 8, 5, 12)
        let keepID = UUID()
        let staleID = UUID()
        let tasks = [
            taskInput(id: keepID, title: "Keep", reminder: date(2026, 8, 5, 16))
        ]
        let keepIdent = NotificationIdentifier.taskReminder(taskID: keepID)
        let staleIdent = NotificationIdentifier.taskReminder(taskID: staleID)
        let foreign = "com.other.app.reminder"

        let plan = NotificationReconcilePlanner.plan(
            tasks: tasks,
            pendingIdentifiers: [keepIdent, staleIdent, foreign, NotificationIdentifier.dailySummary],
            dailySummaryPreferences: DailySummaryPreferences(isEnabled: false),
            dashboardTasks: [],
            now: now,
            calendar: calendar
        )

        #expect(plan.toSchedule.map(\.taskID) == [keepID])
        #expect(plan.toCancel.contains(staleIdent))
        #expect(plan.toCancel.contains(foreign) == false)
        #expect(plan.cancelDailySummary)
        #expect(plan.dailySummary == nil)
    }

    @Test("Changed reminder date appears in schedule set; completed is cancelled")
    func changedAndCompleted() {
        let now = date(2026, 8, 5, 12)
        let id = UUID()
        let tasks = [taskInput(id: id, status: .done, reminder: date(2026, 8, 5, 16))]
        let pending = Set([NotificationIdentifier.taskReminder(taskID: id)])
        let plan = NotificationReconcilePlanner.plan(
            tasks: tasks,
            pendingIdentifiers: pending,
            dailySummaryPreferences: .init(isEnabled: false),
            dashboardTasks: [],
            now: now,
            calendar: calendar
        )
        #expect(plan.toSchedule.isEmpty)
        #expect(plan.toCancel.contains(NotificationIdentifier.taskReminder(taskID: id)))
    }

    // MARK: - Daily summary

    @Test("Daily summary disabled skips; enabled builds count-only body and dashboard link")
    func dailySummary() {
        let now = date(2026, 8, 5, 8)
        let pid = UUID()
        let tasks = [
            DashboardTaskInput(
                title: "Secret title must not appear",
                status: .todo,
                priority: .urgent,
                dueDate: date(2026, 8, 5, 10),
                projectID: pid,
                projectName: "Nexus"
            ),
            DashboardTaskInput(
                title: "Overdue secret",
                status: .todo,
                dueDate: date(2026, 8, 3, 10),
                projectID: pid,
                projectName: "Nexus"
            ),
            DashboardTaskInput(
                title: "Done",
                status: .done,
                priority: .urgent,
                dueDate: date(2026, 8, 5, 9),
                projectID: pid,
                projectName: "Nexus"
            ),
            DashboardTaskInput(
                title: "Archived",
                status: .todo,
                dueDate: date(2026, 8, 5, 9),
                projectID: UUID(),
                projectName: "Old",
                projectIsActive: false
            )
        ]

        #expect(DailySummaryPolicy.scheduleRequest(
            preferences: .init(isEnabled: false),
            tasks: tasks,
            now: now,
            calendar: calendar
        ) == nil)

        let request = DailySummaryPolicy.scheduleRequest(
            preferences: .init(isEnabled: true, hour: 9, minute: 0),
            tasks: tasks,
            now: now,
            calendar: calendar
        )
        #expect(request != nil)
        #expect(request?.content.deepLinkURL == NexusDeepLink.dashboard.url)
        #expect(request?.content.body.contains("Secret") == false)
        #expect(request?.content.body.contains("due today") == true)
        #expect(request?.content.body.contains("overdue") == true)
        #expect(request!.fireDate > now)

        let empty = DailySummaryPolicy.scheduleRequest(
            preferences: .init(isEnabled: true),
            tasks: [],
            now: now,
            calendar: calendar
        )
        #expect(empty == nil)

        let next = DailySummaryPolicy.nextFireDate(hour: 9, minute: 0, after: date(2026, 8, 5, 9, 30), calendar: calendar)
        #expect(calendar.component(.day, from: next) == 6)
    }

    // MARK: - Deep links & identifiers

    @Test("Notification deep links and stable identifiers")
    func deepLinksAndIDs() {
        let id = UUID()
        #expect(NotificationIdentifier.taskReminder(taskID: id) == "nexus.task.\(id.uuidString)")
        #expect(NotificationIdentifier.taskID(from: NotificationIdentifier.taskReminder(taskID: id)) == id)
        #expect(NotificationIdentifier.isNexusOwned(NotificationIdentifier.dailySummary))
        #expect(NotificationIdentifier.isNexusOwned("other") == false)
        #expect(NexusDeepLink(url: NexusDeepLink.task(id).url) == .task(id))
        #expect(NexusDeepLink(url: NexusDeepLink.dashboard.url) == .dashboard)
        #expect(NexusDeepLink(url: URL(string: "nexus://task/bad")!) == nil)
    }

    // MARK: - Schema / mapping

    @Test("Existing tasks default nil reminder; repository clears on complete")
    func schemaAndRepository() throws {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "P")
        let task = try tasks.create(in: project, title: "T")
        #expect(task.reminderDate == nil)

        let future = date(2026, 8, 6, 10)
        try tasks.update(
            task,
            title: "T",
            taskDescription: "",
            status: .todo,
            priority: .none,
            dueDate: nil,
            reminderDate: future,
            notes: ""
        )
        #expect(task.reminderDate == future)

        try tasks.complete(task)
        #expect(task.status == .done)
        #expect(task.reminderDate == nil)

        #expect(NexusSchema.currentVersion == NexusSchemaV4.versionIdentifier)
    }

    @Test("Draft maps reminder fields from model")
    func draftMapping() throws {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "P")
        let future = Date().addingTimeInterval(3600)
        let task = try TaskRepository(context: context).create(
            in: project,
            title: "Remind me",
            reminderDate: future
        )
        let draft = TaskDraft(task: task)
        #expect(draft.hasReminder)
        #expect(draft.resolvedReminderDate == future)
    }
}
