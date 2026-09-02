import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
struct Phase9SubtaskTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeContainer(kind: .inMemory)
    }

    private func seedRoot(_ context: ModelContext, title: String = "Parent") throws -> (Project, TaskItem) {
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Hierarchy")
        let root = try tasks.create(in: project, title: title)
        return (project, root)
    }

    // MARK: - Validation

    @Test("Hierarchy validation: root child OK; subtask cannot parent; self/cycle/mismatch rejected")
    func hierarchyValidation() {
        let parent = UUID()
        let child = UUID()
        let project = UUID()
        let other = UUID()

        #expect(TaskHierarchyPolicy.validateAttach(
            childID: child,
            parentID: parent,
            parentExists: true,
            parentIsRoot: true,
            childProjectID: project,
            parentProjectID: project
        ) == .valid)

        #expect(TaskHierarchyPolicy.validateAttach(
            childID: child,
            parentID: parent,
            parentExists: true,
            parentIsRoot: false,
            childProjectID: project,
            parentProjectID: project
        ) == .parentIsAlreadySubtask)

        #expect(TaskHierarchyPolicy.validateAttach(
            childID: parent,
            parentID: parent,
            parentExists: true,
            parentIsRoot: true,
            childProjectID: project,
            parentProjectID: project
        ) == .selfParenting)

        #expect(TaskHierarchyPolicy.validateAttach(
            childID: child,
            parentID: parent,
            parentExists: false,
            parentIsRoot: true,
            childProjectID: project,
            parentProjectID: project
        ) == .parentNotFound)

        #expect(TaskHierarchyPolicy.validateAttach(
            childID: child,
            parentID: parent,
            parentExists: true,
            parentIsRoot: true,
            childProjectID: project,
            parentProjectID: other
        ) == .projectMismatch)

        #expect(TaskHierarchyPolicy.validateAttach(
            childID: child,
            parentID: parent,
            parentExists: true,
            parentIsRoot: true,
            childHasChildren: true,
            childProjectID: project,
            parentProjectID: project
        ) == .nestedHierarchyNotAllowed)

        #expect(TaskHierarchyPolicy.validateAttach(
            childID: child,
            parentID: parent,
            parentExists: true,
            parentIsRoot: true,
            childProjectID: project,
            parentProjectID: project,
            parentIsDescendantOfChild: true
        ) == .cycleDetected)

        #expect(TaskHierarchyPolicy.canAddSubtasks(isRoot: true))
        #expect(TaskHierarchyPolicy.canAddSubtasks(isRoot: false) == false)
    }

    // MARK: - Creation / progress

    @Test("Create subtask inherits project, status, position; supports labels checklist reminder; roots exclude child")
    func createAndQuery() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let labels = LabelRepository(context: context)
        let checklists = ChecklistRepository(context: context)
        let tasks = TaskRepository(context: context)
        let (project, root) = try seedRoot(context)
        let label = try labels.create(name: "Ship")
        let reminder = Date().addingTimeInterval(8_000)

        let child = try tasks.createSubtask(
            parentTaskID: root.id,
            title: "  Child  step  ",
            status: .todo,
            priority: .high,
            dueDate: Date().addingTimeInterval(86_400),
            reminderDate: reminder,
            notes: "note",
            labelIDs: [label.id]
        )
        #expect(child.title == "Child  step")
        #expect(child.project?.id == project.id)
        #expect(child.parentTask?.id == root.id)
        #expect(child.status == .todo)
        #expect(child.priority == .high)
        #expect(child.reminderDate == reminder)
        #expect((child.labels ?? []).contains(where: { $0.id == label.id }))
        #expect(child.isRoot == false)

        _ = try checklists.createItem(taskID: child.id, title: "Check this")
        #expect((child.checklist ?? []).count == 1)

        let roots = try tasks.fetchRootTasks(projectID: project.id)
        #expect(roots.map(\.id) == [root.id])
        #expect(try tasks.fetchSubtasks(parentTaskID: root.id).map(\.id) == [child.id])

        // Nested rejected
        do {
            _ = try tasks.createSubtask(parentTaskID: child.id, title: "Grandchild")
            Issue.record("Expected nested rejection")
        } catch RepositoryValidationError.hierarchyInvalid(let result) {
            #expect(result == .parentIsAlreadySubtask)
        }
    }

    @Test("Subtask progress: empty, partial, full, reopen; full does not complete parent")
    func progress() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let tasks = TaskRepository(context: context)
        let (_, root) = try seedRoot(context)

        #expect(try tasks.subtaskProgress(parentTaskID: root.id).hasProgress == false)

        let a = try tasks.createSubtask(parentTaskID: root.id, title: "A")
        let b = try tasks.createSubtask(parentTaskID: root.id, title: "B")
        _ = try tasks.createSubtask(parentTaskID: root.id, title: "C")

        try tasks.complete(a)
        try tasks.complete(b)
        var progress = try tasks.subtaskProgress(parentTaskID: root.id)
        #expect(progress.completed == 2)
        #expect(progress.total == 3)
        #expect(progress.isComplete == false)
        #expect(root.status == .todo)

        try tasks.reopen(a)
        progress = try tasks.subtaskProgress(parentTaskID: root.id)
        #expect(progress.completed == 1)

        // complete remaining doesn't finish parent
        try tasks.complete(a)
        try tasks.complete(try tasks.fetchSubtasks(parentTaskID: root.id).first { $0.title == "C" }!)
        progress = try tasks.subtaskProgress(parentTaskID: root.id)
        #expect(progress.isComplete)
        #expect(root.status == .todo)
        #expect(root.completedAt == nil)
    }

    // MARK: - Ordering

    @Test("Subtask ordering: move before/begin/end, no-op, normalize; root Kanban order unaffected")
    func ordering() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let tasks = TaskRepository(context: context)
        let (project, root) = try seedRoot(context)
        let sibling = try tasks.create(in: project, title: "Sibling Root", status: .todo)
        let siblingPos = sibling.position

        let a = try tasks.createSubtask(parentTaskID: root.id, title: "1")
        let b = try tasks.createSubtask(parentTaskID: root.id, title: "2")
        let c = try tasks.createSubtask(parentTaskID: root.id, title: "3")
        #expect(try tasks.fetchSubtasks(parentTaskID: root.id).map(\.id) == [a.id, b.id, c.id])

        #expect(try tasks.reorderSubtask(taskID: c.id, before: a.id))
        #expect(try tasks.fetchSubtasks(parentTaskID: root.id).map(\.id) == [c.id, a.id, b.id])

        #expect(try tasks.reorderSubtask(taskID: c.id, before: nil))
        #expect(try tasks.fetchSubtasks(parentTaskID: root.id).map(\.id) == [a.id, b.id, c.id])

        #expect(try tasks.reorderSubtask(taskID: c.id, before: b.id))
        #expect(try tasks.fetchSubtasks(parentTaskID: root.id).map(\.id) == [a.id, c.id, b.id])
        #expect(try tasks.reorderSubtask(taskID: c.id, before: b.id) == false)
        #expect(try tasks.reorderSubtask(taskID: a.id, before: a.id) == false)

        // Tiny gaps normalize
        if let x = try tasks.fetchTask(id: a.id),
           let y = try tasks.fetchTask(id: c.id),
           let z = try tasks.fetchTask(id: b.id) {
            x.position = 1
            y.position = 1 + 1e-9
            z.position = 1 + 2e-9
            try context.save()
        }
        #expect(try tasks.reorderSubtask(taskID: b.id, before: a.id))
        let ordered = try tasks.fetchSubtasks(parentTaskID: root.id)
        #expect(ordered.map(\.id) == [b.id, a.id, c.id])
        #expect(FractionalPosition.needsNormalization(positions: ordered.map(\.position)) == false)

        // Root sibling position stable
        #expect(try tasks.fetchTask(id: sibling.id)?.position == siblingPos)
        let roots = try tasks.fetchRootTasks(projectID: project.id, status: .todo)
        #expect(roots.map(\.id).contains(root.id))
        #expect(roots.map(\.id).contains(sibling.id))
        #expect(roots.map(\.id).contains(b.id) == false)
    }

    // MARK: - Promotion / deletion

    @Test("Promote child to root keeps project/metadata and assigns root position")
    func promotion() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let tasks = TaskRepository(context: context)
        let labels = LabelRepository(context: context)
        let (project, root) = try seedRoot(context)
        let label = try labels.create(name: "Keep")
        let reminder = Date().addingTimeInterval(5_000)
        let child = try tasks.createSubtask(
            parentTaskID: root.id,
            title: "Promote me",
            status: .inProgress,
            priority: .urgent,
            reminderDate: reminder,
            labelIDs: [label.id]
        )
        try tasks.promoteToRoot(taskID: child.id)

        #expect(child.parentTask == nil)
        #expect(child.isRoot)
        #expect(child.project?.id == project.id)
        #expect(child.status == .inProgress)
        #expect(child.priority == .urgent)
        #expect(child.reminderDate == reminder)
        #expect((child.labels ?? []).contains(where: { $0.id == label.id }))
        #expect(try tasks.fetchRootTasks(projectID: project.id).contains(where: { $0.id == child.id }))
        #expect(try tasks.subtaskProgress(parentTaskID: root.id).total == 0)
    }

    @Test("Delete child keeps parent; delete parent with descendants/promote; labels/checklists cascade correctly")
    func deletionModes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let tasks = TaskRepository(context: context)
        let checklists = ChecklistRepository(context: context)
        let labels = LabelRepository(context: context)
        let (project, root) = try seedRoot(context)
        let label = try labels.create(name: "Survive")

        let doomed = try tasks.createSubtask(parentTaskID: root.id, title: "Doomed")
        let checklistItem = try checklists.createItem(taskID: doomed.id, title: "Gone")
        try tasks.delete(doomed, mode: .deleteDescendants)
        #expect(try tasks.fetchTask(id: doomed.id) == nil)
        #expect(try checklists.fetchItem(id: checklistItem.id) == nil)
        #expect(try tasks.fetchTask(id: root.id) != nil)

        let keepA = try tasks.createSubtask(
            parentTaskID: root.id,
            title: "Keep A",
            status: .review,
            labelIDs: [label.id]
        )
        let keepB = try tasks.createSubtask(parentTaskID: root.id, title: "Keep B", status: .todo)
        _ = try checklists.createItem(taskID: keepA.id, title: "Child checklist")

        try tasks.delete(root, mode: .promoteChildren)
        #expect(try tasks.fetchTask(id: root.id) == nil)
        #expect(keepA.parentTask == nil)
        #expect(keepB.parentTask == nil)
        #expect(keepA.project?.id == project.id)
        #expect(keepA.status == .review)
        #expect((keepA.labels ?? []).contains(where: { $0.id == label.id }))
        #expect(try labels.fetch(id: label.id) != nil)
        #expect(try tasks.fetchRootTasks(projectID: project.id).map(\.id).contains(keepA.id))
        #expect((keepA.checklist ?? []).isEmpty == false)

        // Delete descendants removes children
        let p2 = try tasks.create(in: project, title: "P2")
        let c1 = try tasks.createSubtask(parentTaskID: p2.id, title: "C1")
        try tasks.delete(p2, mode: .deleteDescendants)
        #expect(try tasks.fetchTask(id: p2.id) == nil)
        #expect(try tasks.fetchTask(id: c1.id) == nil)
    }

    // MARK: - Integration

    @Test("Parent/child completion independence; classifiers; search/dashboard exclude children")
    func integrationSafeguards() throws {
        #expect(WidgetReloadClassifier.kinds(for: .subtaskCreated).isEmpty)
        #expect(WidgetReloadClassifier.kinds(for: .subtaskUpdated).isEmpty)
        #expect(WidgetReloadClassifier.kinds(for: .subtaskCompletedOrReopened).isEmpty)
        #expect(WidgetReloadClassifier.kinds(for: .subtaskReordered).isEmpty)
        #expect(WidgetReloadClassifier.kinds(for: .subtaskPromoted).isEmpty == false)
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .subtaskCreated))
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .subtaskReordered) == false)
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .subtaskCompletedOrReopened))

        let container = try makeContainer()
        let context = ModelContext(container)
        let tasks = TaskRepository(context: context)
        let (project, root) = try seedRoot(context, title: "Root Visible")
        let childReminder = Date().addingTimeInterval(9_000)
        let child = try tasks.createSubtask(
            parentTaskID: root.id,
            title: "Hidden Sub Unique token",
            reminderDate: childReminder
        )
        let rootReminder = Date().addingTimeInterval(10_000)
        try tasks.update(
            root,
            title: root.title,
            taskDescription: "",
            status: .todo,
            priority: .none,
            dueDate: nil,
            reminderDate: rootReminder,
            notes: "",
            labelIDs: []
        )

        try tasks.complete(root)
        #expect(root.status == .done)
        #expect(child.status == .todo)
        #expect(child.reminderDate == childReminder)

        // Completing parent does not complete child; reopen parent leaves child independent.
        try tasks.reopen(root)
        #expect(root.status == .todo)
        #expect(child.status == .todo)
        #expect(child.reminderDate == childReminder)

        try tasks.complete(child)
        #expect(child.status == .done)
        #expect(child.reminderDate == nil)
        #expect(root.status == .todo)

        // Search excludes subtask
        let searchableRoot = SearchMapping.task(root)!
        let searchableChild = SearchMapping.task(child)!
        let byChildTitle = SearchBuilder.build(
            query: "Hidden Sub Unique",
            projects: [],
            tasks: [searchableRoot, searchableChild],
            includeArchived: false
        )
        #expect(byChildTitle.taskTotalCount == 0)

        // Dashboard excludes child
        let dash = [
            DashboardMapping.taskInput(from: root)!,
            DashboardMapping.taskInput(from: child)!
        ]
        let snap = DashboardBuilder.build(
            projects: [DashboardMapping.projectInput(from: project)],
            tasks: dash
        )
        #expect(snap.recentlyUpdated.allSatisfy { $0.id != child.id })

        // Widgets exclude child via isRoot filter
        let high = WidgetSnapshotBuilder.highPrioritySnapshot(tasks: dash)
        #expect(high.tasks.allSatisfy { $0.id != child.id })

        // Label list root-only
        let labels = LabelRepository(context: context)
        let lab = try labels.create(name: "L")
        try tasks.update(
            child,
            title: child.title,
            taskDescription: "",
            status: .todo,
            priority: .none,
            dueDate: nil,
            reminderDate: nil,
            notes: "",
            labelIDs: [lab.id]
        )
        let labelTasks = try labels.rootTaskRows(for: lab.id)
        #expect(labelTasks.contains(where: { $0.id == child.id }) == false)

        // Quick Add path: create without parent remains root
        let qa = try tasks.create(in: project, title: "Quick style")
        #expect(qa.isRoot)
    }
}
