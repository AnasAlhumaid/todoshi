import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
struct Phase11RecurrenceTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0) -> Date {
        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        components.hour = h
        components.minute = min
        components.second = 0
        return calendar.date(from: components)!
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeContainer(kind: .inMemory)
    }

    private func seedProject(_ context: ModelContext, name: String = "Recur") throws -> Project {
        try ProjectRepository(context: context).create(name: name)
    }

    // MARK: - Schema

    @Test("Schema V4 is current; recurrence defaults empty; Release policy non-destructive")
    func schemaV4() {
        #expect(NexusSchema.currentVersion == NexusSchemaV4.versionIdentifier)
        #expect(NexusSchemaMigrationPlan.schemas.count == 1)
        #expect(StoreResetPolicy.allowsDestructiveAppGroupReset == {
            #if DEBUG
            true
            #else
            false
            #endif
        }())

        #expect(WidgetReloadClassifier.kinds(for: .recurrenceEnabled).isEmpty)
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .recurrenceEnabled) == false)
        #expect(WidgetReloadClassifier.kinds(for: .recurringOccurrenceGenerated) == NexusWidgetKind.allTaskListKinds)
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .recurringOccurrenceGenerated))
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .resourceOrphanCleanupCompleted) == false)
    }

    // MARK: - Validation / parse

    @Test("Recurrence validation: due required, interval bounds, subtask rejected, invalid raw safe")
    func validation() {
        let weekly = TaskRecurrenceRule(kind: .weekly)
        #expect(TaskRecurrencePolicy.validationIssue(rule: weekly, dueDate: nil, isRoot: true) == .dueDateRequired)
        #expect(TaskRecurrencePolicy.validationIssue(rule: weekly, dueDate: date(2026, 8, 3), isRoot: false) == .subtaskCannotRecur)
        #expect(TaskRecurrencePolicy.validationIssue(rule: weekly, dueDate: date(2026, 8, 3), isRoot: true) == nil)

        #expect(TaskRecurrenceRule(kind: .customDays, interval: 0).interval == 1)
        #expect(TaskRecurrenceRule(kind: .customDays, interval: 400).interval == 365)
        #expect(TaskRecurrenceRule(kind: .weekly, interval: 5).interval == 1)

        #expect(TaskRecurrencePolicy.parse(ruleRaw: "not-a-rule", interval: 1) == nil)
        #expect(TaskRecurrencePolicy.parse(ruleRaw: "daily", interval: 0) == nil)
        #expect(TaskRecurrencePolicy.parse(ruleRaw: "daily", interval: 366) == nil)
        #expect(TaskRecurrencePolicy.parse(ruleRaw: "daily", interval: 1)?.kind == .daily)
        #expect(TaskRecurrencePolicy.parse(ruleRaw: nil, interval: nil) == nil)
    }

    // MARK: - Date calculations

    @Test("Next due: daily, weekdays, weekly, monthly, yearly, custom; time preserved")
    func dateCalculations() {
        let mon = date(2026, 8, 3, 9) // Monday
        let tue = date(2026, 8, 4, 9)
        let fri = date(2026, 8, 7, 9)
        let jan31 = date(2026, 1, 31, 9)
        let feb29 = date(2024, 2, 29, 9)

        let daily = TaskRecurrencePolicy.nextDueDate(
            from: mon,
            rule: TaskRecurrenceRule(kind: .daily),
            calendar: calendar
        )!
        #expect(calendar.isDate(daily, inSameDayAs: tue))
        #expect(calendar.component(.hour, from: daily) == 9)

        let wed = TaskRecurrencePolicy.nextDueDate(
            from: tue,
            rule: TaskRecurrenceRule(kind: .weekdays),
            calendar: calendar
        )!
        #expect(calendar.component(.weekday, from: wed) == 4) // Wednesday

        let monAgain = TaskRecurrencePolicy.nextDueDate(
            from: fri,
            rule: TaskRecurrenceRule(kind: .weekdays),
            calendar: calendar
        )!
        #expect(calendar.component(.weekday, from: monAgain) == 2) // Monday
        #expect(calendar.component(.hour, from: monAgain) == 9)

        let nextWeek = TaskRecurrencePolicy.nextDueDate(
            from: mon,
            rule: TaskRecurrenceRule(kind: .weekly),
            calendar: calendar
        )!
        #expect(calendar.isDate(nextWeek, inSameDayAs: date(2026, 8, 10, 9)))

        let feb = TaskRecurrencePolicy.nextDueDate(
            from: jan31,
            rule: TaskRecurrenceRule(kind: .monthly),
            calendar: calendar
        )!
        #expect(calendar.component(.month, from: feb) == 2)
        #expect(calendar.component(.day, from: feb) == 28) // 2026 non-leap

        let nextYearLeap = TaskRecurrencePolicy.nextDueDate(
            from: feb29,
            rule: TaskRecurrenceRule(kind: .yearly),
            calendar: calendar
        )!
        #expect(calendar.component(.year, from: nextYearLeap) == 2025)
        #expect(calendar.component(.month, from: nextYearLeap) == 2)
        #expect(calendar.component(.day, from: nextYearLeap) == 28)

        let customDays = TaskRecurrencePolicy.nextDueDate(
            from: mon,
            rule: TaskRecurrenceRule(kind: .customDays, interval: 3),
            calendar: calendar
        )!
        #expect(calendar.isDate(customDays, inSameDayAs: date(2026, 8, 6, 9)))

        let customWeeks = TaskRecurrencePolicy.nextDueDate(
            from: mon,
            rule: TaskRecurrenceRule(kind: .customWeeks, interval: 2),
            calendar: calendar
        )!
        #expect(calendar.isDate(customWeeks, inSameDayAs: date(2026, 8, 17, 9)))

        let customMonths = TaskRecurrencePolicy.nextDueDate(
            from: jan31,
            rule: TaskRecurrenceRule(kind: .customMonths, interval: 1),
            calendar: calendar
        )!
        #expect(calendar.component(.day, from: customMonths) == 28)
    }

    @Test("Reminder offset preserved; past next reminder cleared")
    func reminderOffset() {
        let due = date(2026, 8, 7, 17)
        let reminder = date(2026, 8, 7, 9)
        let nextDue = date(2026, 8, 14, 17)
        let now = date(2026, 8, 7, 12)

        let carried = TaskRecurrencePolicy.nextReminderDate(
            sourceDue: due,
            sourceReminder: reminder,
            nextDue: nextDue,
            now: now
        )!
        #expect(calendar.isDate(carried, inSameDayAs: date(2026, 8, 14, 9)))
        #expect(calendar.component(.hour, from: carried) == 9)

        let expired = TaskRecurrencePolicy.nextReminderDate(
            sourceDue: due,
            sourceReminder: reminder,
            nextDue: date(2026, 8, 8, 17),
            now: date(2026, 8, 10, 12)
        )
        #expect(expired == nil)

        #expect(
            TaskRecurrencePolicy.nextReminderDate(
                sourceDue: due,
                sourceReminder: nil,
                nextDue: nextDue,
                now: now
            ) == nil
        )
    }

    // MARK: - Generation

    @Test("Complete generates next occurrence; idempotent; reopen keeps successor")
    func completeGeneratesOnce() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try seedProject(context)
        let tasks = TaskRepository(context: context)
        let due = date(2026, 8, 3, 9)
        let completeAt = date(2026, 8, 5, 15) // late mid-week

        let task = try tasks.create(
            in: project,
            title: "Standup",
            dueDate: due,
            notes: "Bring notes",
            recurrenceRule: TaskRecurrenceRule(kind: .weekly),
            at: date(2026, 8, 1)
        )
        #expect(task.isRecurring)
        #expect(task.recurrenceSeriesID != nil)
        let series = task.recurrenceSeriesID!

        try tasks.complete(task, at: completeAt)
        #expect(task.status == .done)
        #expect(task.completedAt == completeAt)
        #expect(task.nextOccurrenceID != nil)

        let next = try tasks.fetchTask(id: task.nextOccurrenceID!)
        #expect(next != nil)
        #expect(next?.title == "Standup")
        #expect(next?.notes == "Bring notes")
        #expect(next?.status == .todo)
        #expect(next?.completedAt == nil)
        #expect(next?.recurrenceSeriesID == series)
        #expect(next?.recurrenceGeneration == 1)
        #expect(next?.previousOccurrenceID == task.id)
        #expect(calendar.isDate(next!.dueDate!, inSameDayAs: date(2026, 8, 10, 9)))
        #expect(calendar.component(.hour, from: next!.dueDate!) == 9)

        let rootsAfter = try tasks.fetchRootTasks(projectID: project.id)
        #expect(rootsAfter.count == 2)

        try tasks.complete(task, at: completeAt.addingTimeInterval(60))
        #expect(try tasks.fetchRootTasks(projectID: project.id).count == 2)

        try tasks.reopen(task, at: date(2026, 8, 6))
        #expect(task.status == .todo)
        #expect(task.nextOccurrenceID == next?.id)
        #expect(try tasks.fetchRootTasks(projectID: project.id).count == 2)

        try tasks.complete(task, at: date(2026, 8, 6, 12))
        #expect(try tasks.fetchRootTasks(projectID: project.id).count == 2)
    }

    @Test("Kanban move to Done generates next occurrence")
    func kanbanMoveGenerates() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try seedProject(context)
        let tasks = TaskRepository(context: context)
        let task = try tasks.create(
            in: project,
            title: "Deploy",
            dueDate: date(2026, 8, 1),
            recurrenceRule: TaskRecurrenceRule(kind: .daily)
        )
        try tasks.move(taskID: task.id, to: .done, before: nil, at: date(2026, 8, 1, 18))
        #expect(task.nextOccurrenceID != nil)
        let next = try tasks.fetchTask(id: task.nextOccurrenceID!)
        #expect(next?.status == .todo)
        #expect(calendar.isDate(next!.dueDate!, inSameDayAs: date(2026, 8, 2)))
    }

    @Test("Field copy: labels, checklist reset, text resources; files and subtasks excluded")
    func fieldCopy() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try seedProject(context)
        let tasks = TaskRepository(context: context)
        let labels = LabelRepository(context: context)
        let checklists = ChecklistRepository(context: context)

        let fileRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusRecur-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fileRoot, withIntermediateDirectories: true)
        let store = TaskResourceFileStore(rootURL: fileRoot)
        TaskResourceFileAccess.current = store
        let resources = TaskResourceRepository(context: context, fileStore: store)

        let label = try labels.create(name: "Ops", colorHex: "#FF0000")
        let due = date(2026, 9, 1, 17)
        let reminder = date(2026, 9, 1, 9)
        let task = try tasks.create(
            in: project,
            title: "Routine",
            taskDescription: "Desc",
            priority: .high,
            dueDate: due,
            reminderDate: reminder,
            notes: "Notes",
            labelIDs: [label.id],
            recurrenceRule: TaskRecurrenceRule(kind: .weekly),
            at: date(2026, 8, 20)
        )

        try checklists.replaceChecklist(
            taskID: task.id,
            drafts: [
                ChecklistItemDraft(title: "Step A", isCompleted: true, position: 1),
                ChecklistItemDraft(title: "Step B", isCompleted: false, position: 2)
            ]
        )
        _ = try resources.createLink(
            taskID: task.id,
            title: "Docs",
            url: URL(string: "https://example.com")!
        )
        _ = try resources.createTextResource(taskID: task.id, kind: .text, title: "Note", body: "hello")
        _ = try resources.createTextResource(taskID: task.id, kind: .codeSnippet, title: "Code", body: "print(1)")
        _ = try resources.createTextResource(taskID: task.id, kind: .terminalCommand, title: "Cmd", body: "ls")

        let fileResourceID = UUID()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("file-\(UUID()).txt")
        try Data("blob".utf8).write(to: tmp)
        let imported = try store.importFile(from: tmp, taskID: task.id, resourceID: fileResourceID)
        _ = try resources.createImportedFile(
            taskID: task.id,
            resourceID: fileResourceID,
            importedFile: imported
        )

        _ = try tasks.createSubtask(parentTaskID: task.id, title: "Child only")

        try tasks.complete(task, at: date(2026, 9, 2, 10))
        let next = try tasks.fetchTask(id: task.nextOccurrenceID!)!
        #expect(next.priority == .high)
        #expect(next.taskDescription == "Desc")
        #expect(Set((next.labels ?? []).map(\.id)) == [label.id])
        #expect((next.subtasks ?? []).isEmpty)
        #expect(task.subtasks?.count == 1)

        let nextChecklist = (next.checklist ?? []).sorted { $0.position < $1.position }
        #expect(nextChecklist.map(\.title) == ["Step A", "Step B"])
        #expect(nextChecklist.allSatisfy { !$0.isCompleted })
        #expect(Set(nextChecklist.map(\.id)).isDisjoint(with: Set((task.checklist ?? []).map(\.id))))

        let nextResources = (next.resources ?? []).sorted { $0.position < $1.position }
        #expect(nextResources.count == 4)
        #expect(nextResources.allSatisfy { !$0.kind.isFileBacked })
        #expect(nextResources.contains { $0.kind == .link && $0.externalURLString == "https://example.com" })
        #expect(nextResources.contains { $0.kind == .codeSnippet && $0.body == "print(1)" })

        #expect(next.reminderDate != nil)
        #expect(calendar.component(.hour, from: next.reminderDate!) == 9)
        #expect(calendar.isDate(next.dueDate!, inSameDayAs: date(2026, 9, 8, 17)))
    }

    @Test("Create with recurrence requires due date; subtask path rejects recurrence")
    func createBoundaries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try seedProject(context)
        let tasks = TaskRepository(context: context)

        do {
            _ = try tasks.create(
                in: project,
                title: "No due",
                recurrenceRule: TaskRecurrenceRule(kind: .daily)
            )
            Issue.record("Expected due date validation")
        } catch RepositoryValidationError.recurrenceInvalid(let issue) {
            #expect(issue == .dueDateRequired)
        }

        let root = try tasks.create(
            in: project,
            title: "Root",
            dueDate: date(2026, 8, 1),
            recurrenceRule: TaskRecurrenceRule(kind: .daily)
        )
        let child = try tasks.createSubtask(parentTaskID: root.id, title: "Child")
        do {
            try tasks.update(
                child,
                title: child.title,
                taskDescription: "",
                status: .todo,
                priority: .none,
                dueDate: date(2026, 8, 2),
                notes: "",
                recurrenceRule: TaskRecurrenceRule(kind: .weekly),
                updateRecurrence: true
            )
            Issue.record("Expected subtask recurrence rejection")
        } catch RepositoryValidationError.recurrenceInvalid(let issue) {
            #expect(issue == .subtaskCannotRecur)
        }
    }

    @Test("Disable recurrence stops generation; delete occurrence leaves siblings")
    func stopAndDelete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try seedProject(context)
        let tasks = TaskRepository(context: context)

        let first = try tasks.create(
            in: project,
            title: "Series",
            dueDate: date(2026, 8, 1),
            recurrenceRule: TaskRecurrenceRule(kind: .daily)
        )
        try tasks.complete(first, at: date(2026, 8, 1, 18))
        let second = try tasks.fetchTask(id: first.nextOccurrenceID!)!

        try tasks.update(
            second,
            title: second.title,
            taskDescription: "",
            status: .todo,
            priority: .none,
            dueDate: second.dueDate,
            notes: "",
            recurrenceRule: nil,
            updateRecurrence: true
        )
        #expect(second.recurrenceRule == nil)
        try tasks.complete(second, at: date(2026, 8, 2, 18))
        #expect(second.nextOccurrenceID == nil)
        #expect(try tasks.fetchRootTasks(projectID: project.id).count == 2)

        let aliveID = first.id
        try tasks.delete(second)
        #expect(try tasks.fetchTask(id: aliveID) != nil)
        #expect(try tasks.fetchRootTasks(projectID: project.id).count == 1)
    }

    @Test("Editing current occurrence does not mutate already-generated successor")
    func editNotRetroactive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try seedProject(context)
        let tasks = TaskRepository(context: context)

        let first = try tasks.create(
            in: project,
            title: "Original",
            dueDate: date(2026, 8, 1),
            recurrenceRule: TaskRecurrenceRule(kind: .weekly)
        )
        try tasks.complete(first, at: date(2026, 8, 1, 12))
        let second = try tasks.fetchTask(id: first.nextOccurrenceID!)!

        try tasks.update(
            first,
            title: "Changed after generate",
            taskDescription: "",
            status: .done,
            priority: .none,
            dueDate: first.dueDate,
            notes: "x",
            updateRecurrence: false
        )
        #expect(second.title == "Original")
    }

    @Test("Project archive preserves recurrence; delete project removes tasks")
    func projectArchiveDelete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Archive Me")
        let task = try tasks.create(
            in: project,
            title: "Keep rule",
            dueDate: date(2026, 8, 1),
            recurrenceRule: TaskRecurrenceRule(kind: .monthly)
        )
        try projects.archive(project)
        #expect(task.recurrenceRule?.kind == .monthly)
        try projects.restore(project)
        #expect(task.recurrenceRule?.kind == .monthly)

        let other = try projects.create(name: "Drop")
        _ = try tasks.create(
            in: other,
            title: "Gone",
            dueDate: date(2026, 8, 1),
            recurrenceRule: TaskRecurrenceRule(kind: .daily)
        )
        try projects.delete(other)
        #expect(try tasks.fetchRootTasks(projectID: other.id).isEmpty)
    }

    @Test("Generated root appears in root query and search")
    func surfaces() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try seedProject(context)
        let tasks = TaskRepository(context: context)
        let first = try tasks.create(
            in: project,
            title: "Findable next",
            dueDate: date(2026, 8, 1),
            recurrenceRule: TaskRecurrenceRule(kind: .daily)
        )
        try tasks.complete(first, at: date(2026, 8, 1, 12))
        let next = try tasks.fetchTask(id: first.nextOccurrenceID!)!
        let roots = try tasks.fetchRootTasks(projectID: project.id).filter { $0.status == .todo }
        #expect(roots.contains { $0.id == next.id })

        let searchable = SearchableTask(
            id: next.id,
            title: next.title,
            status: next.status,
            updatedAt: next.updatedAt,
            isRoot: true,
            projectID: project.id,
            projectName: project.name
        )
        let results = SearchBuilder.build(
            query: "Findable",
            projects: [],
            tasks: [searchable],
            includeArchived: false
        )
        #expect(results.tasks.contains { $0.task.id == next.id })
    }

    @Test("Draft recurrence fields and summaries")
    func draftRecurrence() {
        var draft = TaskDraft()
        draft.hasDueDate = true
        draft.dueDate = date(2026, 8, 1)
        draft.setRecurrenceEnabled(true)
        draft.recurrenceKind = .customWeeks
        draft.recurrenceInterval = 2
        #expect(draft.resolvedRecurrenceRule?.summary == "Every 2 weeks")
        #expect(draft.recurrenceValidationIssue == nil)

        draft.hasDueDate = false
        #expect(draft.recurrenceValidationIssue == .dueDateRequired)

        draft.parentTaskID = UUID()
        draft.hasDueDate = true
        draft.setRecurrenceEnabled(true)
        #expect(draft.resolvedRecurrenceRule == nil)
    }
}
