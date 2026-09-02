import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
struct Phase8ChecklistTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeContainer(kind: .inMemory)
    }

    private func seedTask(_ context: ModelContext, title: String = "Parent") throws -> (Project, TaskItem) {
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Checklist Proj")
        let task = try tasks.create(in: project, title: title)
        return (project, task)
    }

    // MARK: - Validation

    @Test("Checklist validation: empty, trim, collapse, length, Arabic, English, duplicates allowed")
    func validationRules() {
        #expect(ChecklistValidation.normalizeTitle("  Do   this  ") == "Do this")
        #expect(ChecklistValidation.issue(title: "   ") == .emptyTitle)
        #expect(ChecklistValidation.issue(title: "") == .emptyTitle)
        #expect(ChecklistValidation.issue(title: String(repeating: "a", count: 121)) == .tooLong)
        #expect(ChecklistValidation.issue(title: String(repeating: "a", count: 120)) == nil)
        #expect(ChecklistValidation.issue(title: "Implement login") == nil)
        #expect(ChecklistValidation.issue(title: "تنفيذ شاشة الدخول") == nil)
        // Duplicates are allowed at validation layer (no uniqueness check)
        #expect(ChecklistValidation.issue(title: "Same") == nil)
        #expect(ChecklistValidation.issue(title: "Same") == nil)
        // Does not alter casing
        #expect(ChecklistValidation.normalizeTitle("  ABC  Def  ") == "ABC Def")
    }

    // MARK: - Progress

    @Test("Checklist progress: empty, partial, full; completion does not imply parent done")
    func progressValues() {
        #expect(ChecklistProgress.from(completedFlags: []).hasProgress == false)
        #expect(ChecklistProgress.from(completedFlags: []).isComplete == false)

        let zero = ChecklistProgress.from(completedFlags: [false, false])
        #expect(zero.completed == 0)
        #expect(zero.total == 2)
        #expect(zero.fraction == 0)
        #expect(zero.isComplete == false)
        #expect(zero.compactLabel == "0/2")

        let partial = ChecklistProgress.from(completedFlags: [true, false, true])
        #expect(partial.completed == 2)
        #expect(partial.total == 3)
        #expect(abs(partial.fraction - 2.0 / 3.0) < 0.0001)
        #expect(partial.isComplete == false)

        let full = ChecklistProgress.from(completedFlags: [true, true])
        #expect(full.isComplete)
        #expect(full.fraction == 1)
        #expect(full.compactLabel == "2/2")
    }

    // MARK: - CRUD + cascade

    @Test("Create, rename, complete, reopen, delete checklist; cascade and parent timestamp")
    func crudAndCascade() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, task) = try seedTask(context)
        let checklists = ChecklistRepository(context: context)
        let tasks = TaskRepository(context: context)

        let t1 = Date(timeIntervalSince1970: 1_700_000_100)
        let a = try checklists.createItem(taskID: task.id, title: "  First  step  ", at: t1)
        #expect(a.title == "First step")
        #expect(a.isCompleted == false)
        #expect(try checklists.fetchItems(taskID: task.id).count == 1)
        #expect(task.updatedAt == t1)

        // Duplicate titles allowed
        let a2 = try checklists.createItem(taskID: task.id, title: "First step", at: t1.addingTimeInterval(1))
        #expect(a2.title == "First step")

        try checklists.updateItem(itemID: a.id, title: "  Renamed  ", at: t1.addingTimeInterval(2))
        #expect(try checklists.fetchItem(id: a.id)?.title == "Renamed")

        let statusBefore = task.status
        let reminder = Date().addingTimeInterval(7200)
        try tasks.update(
            task,
            title: task.title,
            taskDescription: "",
            status: .todo,
            priority: .high,
            dueDate: nil,
            reminderDate: reminder,
            notes: "",
            labelIDs: []
        )
        #expect(task.reminderDate != nil)

        let t2 = Date(timeIntervalSince1970: 1_700_000_200)
        try checklists.setCompleted(itemID: a.id, isCompleted: true, at: t2)
        #expect(try checklists.fetchItem(id: a.id)?.isCompleted == true)
        #expect(task.status == statusBefore)
        #expect(task.reminderDate == reminder)
        #expect(task.updatedAt == t2)

        try checklists.setCompleted(itemID: a.id, isCompleted: false, at: t2.addingTimeInterval(1))
        #expect(try checklists.fetchItem(id: a.id)?.isCompleted == false)

        // Complete all does not complete parent
        let b = try checklists.createItem(taskID: task.id, title: "Second")
        try checklists.setCompleted(itemID: a.id, isCompleted: true)
        try checklists.setCompleted(itemID: a2.id, isCompleted: true)
        try checklists.setCompleted(itemID: b.id, isCompleted: true)
        #expect(task.status == .todo)
        #expect(task.completedAt == nil)

        try checklists.deleteItem(itemID: a2.id)
        #expect(try checklists.fetchItems(taskID: task.id).count == 2)
        #expect(try tasks.fetchTask(id: task.id) != nil)

        // Cascade when task deleted
        let ids = try checklists.fetchItems(taskID: task.id).map(\.id)
        try tasks.delete(task, mode: .deleteDescendants)
        for id in ids {
            #expect(try checklists.fetchItem(id: id) == nil)
        }
    }

    // MARK: - Draft / replace

    @Test("Draft mapping, replace create/update/delete, empty discard, preserve IDs, cancel-safe")
    func draftAndReplace() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, task) = try seedTask(context)
        let checklists = ChecklistRepository(context: context)

        let i1 = try checklists.createItem(taskID: task.id, title: "Keep")
        let i2 = try checklists.createItem(taskID: task.id, title: "Update me")
        let i3 = try checklists.createItem(taskID: task.id, title: "Remove")

        var drafts = ChecklistDraftBuilder.drafts(from: try checklists.fetchItems(taskID: task.id))
        #expect(drafts.count == 3)
        #expect(drafts[0].persistedItemID == i1.id)
        #expect(drafts[0].id == i1.id)

        let temp = ChecklistItemDraft(title: "  New  one  ")
        #expect(temp.persistedItemID == nil)
        drafts.append(temp)
        drafts.append(ChecklistItemDraft(title: "   ")) // discarded
        drafts.removeAll { $0.persistedItemID == i3.id }
        if let idx = drafts.firstIndex(where: { $0.persistedItemID == i2.id }) {
            drafts[idx].title = "Updated"
            drafts[idx].isCompleted = true
        }

        // Cancel simulation: original data still present before replace
        #expect(try checklists.fetchItems(taskID: task.id).count == 3)

        try checklists.replaceChecklist(taskID: task.id, drafts: drafts)
        let after = try checklists.fetchItems(taskID: task.id)
        #expect(after.count == 3)
        #expect(Set(after.map(\.title)) == Set(["Keep", "New one", "Updated"]))
        #expect(after.first(where: { $0.id == i1.id })?.title == "Keep")
        #expect(after.first(where: { $0.id == i2.id })?.isCompleted == true)
        #expect(after.contains(where: { $0.id == i3.id }) == false)
        #expect(after.contains(where: { $0.title == "New one" }))

        // Stale persisted ID treated as new insert (item deleted under us)
        var staleDraft = ChecklistItemDraft(title: "Orphan draft", persistedItemID: UUID())
        staleDraft.isCompleted = true
        try checklists.replaceChecklist(taskID: task.id, drafts: [staleDraft])
        let orphan = try checklists.fetchItems(taskID: task.id)
        #expect(orphan.count == 1)
        #expect(orphan[0].title == "Orphan draft")
        #expect(orphan[0].id != staleDraft.persistedItemID)
    }

    // MARK: - Ordering

    @Test("Fractional ordering, move before/begin/end, no-op self, normalize gaps, isolation")
    func ordering() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let checklists = ChecklistRepository(context: context)
        let (_, taskA) = try seedTask(context, title: "A")
        let (_, taskB) = try seedTask(context, title: "B")

        let a1 = try checklists.createItem(taskID: taskA.id, title: "1")
        let a2 = try checklists.createItem(taskID: taskA.id, title: "2")
        let a3 = try checklists.createItem(taskID: taskA.id, title: "3")
        let b1 = try checklists.createItem(taskID: taskB.id, title: "Other")
        let bPos = b1.position

        #expect(try checklists.fetchItems(taskID: taskA.id).map(\.id) == [a1.id, a2.id, a3.id])

        // Move to beginning: a3 before a1
        #expect(try checklists.moveItem(itemID: a3.id, before: a1.id))
        #expect(try checklists.fetchItems(taskID: taskA.id).map(\.id) == [a3.id, a1.id, a2.id])

        // Move to end
        #expect(try checklists.moveItem(itemID: a3.id, before: nil))
        #expect(try checklists.fetchItems(taskID: taskA.id).map(\.id) == [a1.id, a2.id, a3.id])

        // Move before
        #expect(try checklists.moveItem(itemID: a3.id, before: a2.id))
        #expect(try checklists.fetchItems(taskID: taskA.id).map(\.id) == [a1.id, a3.id, a2.id])

        // No-op: already immediately before target
        #expect(try checklists.moveItem(itemID: a3.id, before: a2.id) == false)
        // Self-move
        #expect(try checklists.moveItem(itemID: a1.id, before: a1.id) == false)

        // Tiny gaps → normalize while preserving relative order
        if let x = try checklists.fetchItem(id: a1.id),
           let y = try checklists.fetchItem(id: a3.id),
           let z = try checklists.fetchItem(id: a2.id) {
            x.position = 1.0
            y.position = 1.0 + 1e-9
            z.position = 1.0 + 2e-9
            try context.save()
        }
        #expect(try checklists.moveItem(itemID: a2.id, before: a1.id))
        let reordered = try checklists.fetchItems(taskID: taskA.id)
        #expect(reordered.map(\.id) == [a2.id, a1.id, a3.id])
        let positions = reordered.map(\.position)
        #expect(FractionalPosition.needsNormalization(positions: positions) == false)

        // Other task unaffected
        #expect(try checklists.fetchItem(id: b1.id)?.position == bPos)
        #expect(try checklists.fetchItems(taskID: taskB.id).map(\.id) == [b1.id])

        // Initial draft positions follow order
        let drafts = [
            ChecklistItemDraft(title: "x"),
            ChecklistItemDraft(title: "y"),
            ChecklistItemDraft(title: "z")
        ]
        let prepared = ChecklistDraftBuilder.preparedForSave(drafts)
        #expect(prepared.map(\.title) == ["x", "y", "z"])
        #expect(prepared[0].position < prepared[1].position)
        #expect(prepared[1].position < prepared[2].position)
    }

    // MARK: - Integration safeguards

    @Test("Checklist-only changes skip notifications and widgets; search ignores checklist text")
    func integrationSafeguards() throws {
        #expect(WidgetReloadClassifier.kinds(for: .checklistUpdated).isEmpty)
        #expect(WidgetReloadClassifier.kinds(for: .checklistItemToggled).isEmpty)
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .checklistUpdated) == false)
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .checklistItemToggled) == false)
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .taskReminderChanged))

        let container = try makeContainer()
        let context = ModelContext(container)
        let labels = LabelRepository(context: context)
        let checklists = ChecklistRepository(context: context)
        let tasks = TaskRepository(context: context)
        let (project, task) = try seedTask(context)
        let label = try labels.create(name: "Urgent")
        try tasks.update(
            task,
            title: "Ship login screen",
            taskDescription: "",
            status: .todo,
            priority: .high,
            dueDate: nil,
            reminderDate: Date().addingTimeInterval(10_000),
            notes: "",
            labelIDs: [label.id]
        )
        let reminder = task.reminderDate
        let status = task.status
        let labelCount = (task.labels ?? []).count

        _ = try checklists.createItem(taskID: task.id, title: "UniqueChecklistToken-XYZ")
        try checklists.setCompleted(
            itemID: try checklists.fetchItems(taskID: task.id)[0].id,
            isCompleted: true
        )

        #expect(task.reminderDate == reminder)
        #expect(task.status == status)
        #expect((task.labels ?? []).count == labelCount)
        #expect(task.updatedAt > task.createdAt)

        let searchable = SearchableTask(
            id: task.id,
            title: task.title,
            taskDescription: task.taskDescription,
            notes: task.notes,
            status: task.status,
            priority: task.priority,
            dueDate: task.dueDate,
            updatedAt: task.updatedAt,
            isRoot: task.isRoot,
            projectID: project.id,
            projectName: project.name,
            labels: (task.labels ?? []).map { SearchableLabel(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
        )
        let byTitle = SearchBuilder.build(
            query: "login",
            projects: [],
            tasks: [searchable],
            includeArchived: false
        )
        #expect(byTitle.taskTotalCount == 1)

        let byChecklist = SearchBuilder.build(
            query: "UniqueChecklistToken-XYZ",
            projects: [],
            tasks: [searchable],
            includeArchived: false
        )
        #expect(byChecklist.taskTotalCount == 0)

        // Widget snapshots use DashboardTaskInput without checklist fields
        let dash = DashboardTaskInput(
            id: task.id,
            title: task.title,
            status: task.status,
            priority: task.priority,
            dueDate: task.dueDate,
            updatedAt: task.updatedAt,
            isRoot: true,
            projectID: project.id,
            projectName: project.name,
            projectIsActive: true
        )
        let snap = WidgetSnapshotBuilder.highPrioritySnapshot(tasks: [dash])
        #expect(snap.tasks.count == 1)
        #expect(snap.tasks[0].title == "Ship login screen")
    }

    @Test("TaskDraft checklist validity allows empty rows and rejects overlong non-empty titles")
    func taskDraftChecklistValidity() {
        var draft = TaskDraft(title: "OK")
        draft.checklistItems = [
            ChecklistItemDraft(title: "   "),
            ChecklistItemDraft(title: "Fine")
        ]
        #expect(draft.checklistDraftsAreValid)
        #expect(draft.isValid)

        draft.checklistItems.append(ChecklistItemDraft(title: String(repeating: "b", count: 121)))
        #expect(draft.checklistDraftsAreValid == false)
        #expect(draft.isValid == false)

        draft.title = ""
        draft.checklistItems = []
        #expect(draft.isValid == false)
    }
}
