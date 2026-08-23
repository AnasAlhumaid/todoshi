import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
struct Phase7LabelsTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeContainer(kind: .inMemory)
    }

    // MARK: - Validation

    @Test("Label validation: trim, collapse whitespace, length, duplicates, Arabic")
    func validationRules() {
        #expect(LabelValidation.normalizeDisplayName("  Bug  Feature  ") == "Bug Feature")
        #expect(LabelValidation.issue(name: "   ", colorHex: LabelColorCatalog.defaultHex, existingNames: []) == .emptyName)
        #expect(LabelValidation.issue(
            name: String(repeating: "a", count: 31),
            colorHex: LabelColorCatalog.defaultHex,
            existingNames: []
        ) == .tooLong)
        #expect(LabelValidation.issue(
            name: "Bug",
            colorHex: LabelColorCatalog.defaultHex,
            existingNames: ["bug"]
        ) == .duplicateName)
        #expect(LabelValidation.issue(
            name: "  Bug  ",
            colorHex: LabelColorCatalog.defaultHex,
            existingNames: ["Bug"]
        ) == .duplicateName)
        #expect(LabelValidation.namesConflict("Búg", "Bug"))
        #expect(LabelValidation.issue(
            name: "إصلاح",
            colorHex: LabelColorCatalog.defaultHex,
            existingNames: []
        ) == nil)
        #expect(LabelValidation.issue(
            name: "Feature",
            colorHex: LabelColorCatalog.defaultHex,
            existingNames: [],
            excludingLabelID: UUID(),
            existingLabels: [(id: UUID(), name: "Other")]
        ) == nil)

        let id = UUID()
        #expect(LabelValidation.issue(
            name: "Bug",
            colorHex: LabelColorCatalog.defaultHex,
            existingNames: [],
            excludingLabelID: id,
            existingLabels: [(id: id, name: "Bug")]
        ) == nil)

        #expect(LabelValidation.issue(
            name: "OK",
            colorHex: "#NOTREAL",
            existingNames: []
        ) == .invalidColor)
    }

    // MARK: - CRUD

    @Test("Create, edit, delete labels; project delete preserves global labels")
    func crud() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let labels = LabelRepository(context: context)
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)

        let bug = try labels.create(name: "  Bug  ", colorHex: "#E85D75")
        #expect(bug.name == "Bug")
        let feature = try labels.create(name: "Feature", colorHex: "#3DBB7A")

        do {
            _ = try labels.create(name: "bug")
            Issue.record("Expected duplicate")
        } catch RepositoryValidationError.duplicateLabelName {
            // expected
        }

        try labels.update(labelID: bug.id, name: "Defect", colorHex: "#5B8DEF")
        #expect(try labels.fetch(id: bug.id)?.name == "Defect")
        #expect(try labels.fetch(id: bug.id)?.colorHex == "#5B8DEF")

        let project = try projects.create(name: "App")
        let task = try tasks.create(in: project, title: "Login", labelIDs: [bug.id, feature.id])
        #expect((task.labels ?? []).count == 2)
        let reminder = Date().addingTimeInterval(3600)
        try tasks.update(
            task,
            title: "Login",
            taskDescription: "",
            status: .todo,
            priority: .none,
            dueDate: nil,
            reminderDate: reminder,
            notes: "",
            labelIDs: [feature.id]
        )
        #expect(task.reminderDate == reminder)
        #expect(Set((task.labels ?? []).map(\.id)) == [feature.id])

        try labels.delete(labelID: feature.id)
        #expect(try tasks.fetchTask(id: task.id) != nil)
        #expect((task.labels ?? []).isEmpty)
        #expect(task.reminderDate == reminder)

        try labels.delete(labelID: bug.id)
        try projects.delete(project)
        // Global labels must survive project deletion:
        let kept = try labels.create(name: "iOS")
        let doomed = try projects.create(name: "Temp")
        _ = try tasks.create(in: doomed, title: "T", labelIDs: [kept.id])
        try projects.delete(doomed)
        #expect(try labels.fetch(id: kept.id) != nil)
    }

    // MARK: - Assignment

    @Test("Assign, replace, duplicate prevention; draft labels only apply on save")
    func assignment() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let labels = LabelRepository(context: context)
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)

        let a = try labels.create(name: "A")
        let b = try labels.create(name: "B")
        let project = try projects.create(name: "P")
        let task = try tasks.create(in: project, title: "Work")

        try labels.assign(labelID: a.id, to: task.id)
        try labels.assign(labelID: a.id, to: task.id) // no-op
        #expect((task.labels ?? []).count == 1)

        try labels.assign(labelID: b.id, to: task.id)
        #expect((task.labels ?? []).count == 2)

        try labels.remove(labelID: a.id, from: task.id)
        #expect((task.labels ?? []).map(\.id) == [b.id])

        let before = task.updatedAt
        try labels.replaceLabels(for: task.id, with: [a.id, b.id])
        #expect(Set((task.labels ?? []).map(\.id)) == [a.id, b.id])
        #expect(task.updatedAt >= before)

        var draft = TaskDraft(task: task)
        draft.labelIDs = [a.id]
        #expect(Set((task.labels ?? []).map(\.id)) == [a.id, b.id]) // not mutates until save

        draft.labelIDs = [a.id, b.id]
        draft.pruneMissingLabels(validIDs: [b.id])
        #expect(draft.labelIDs == [b.id])
    }

    // MARK: - Counts and list ordering

    @Test("Label task counts and ordered list; root only; archived excluded by default")
    func countsAndList() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let labels = LabelRepository(context: context)
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)

        let label = try labels.create(name: "UI")
        let active = try projects.create(name: "Zeta")
        let early = try projects.create(name: "Alpha")
        let archived = try projects.create(name: "Arch")
        try projects.archive(archived)

        let t1 = try tasks.create(in: early, title: "First", status: .todo, priority: .low, labelIDs: [label.id])
        let t2 = try tasks.create(in: early, title: "High", status: .inProgress, priority: .urgent, labelIDs: [label.id])
        let t3 = try tasks.create(in: active, title: "Other", status: .todo, labelIDs: [label.id])
        _ = try tasks.create(in: archived, title: "Hidden", labelIDs: [label.id])

        // Subtask with same label should not appear in root list
        let root = try tasks.fetchTask(id: t1.id)!
        let child = TaskItem(title: "Child", project: early, parentTask: root)
        child.labels = [label]
        context.insert(child)
        try context.save()

        let summaries = try labels.summaries()
        #expect(summaries.first(where: { $0.id == label.id })?.assignedTaskCount == 5) // all task relations including subtask + archived

        let list = try labels.rootTaskRows(for: label.id, includeArchived: false)
        #expect(list.map(\.id).contains(child.id) == false)
        #expect(list.map(\.title).contains("Hidden") == false)
        // Alpha project before Zeta; within Alpha: inProgress before todo
        #expect(list.first?.title == "High")
        #expect(list.map(\.id).contains(t2.id))
        #expect(list.map(\.id).contains(t3.id))

        let withArchived = try labels.rootTaskRows(for: label.id, includeArchived: true)
        #expect(withArchived.map(\.title).contains("Hidden"))
    }

    // MARK: - Search

    @Test("Search finds tasks by label; removal and deletion clear match; no duplicates")
    func searchIntegration() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let labels = LabelRepository(context: context)
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)

        let bug = try labels.create(name: "Bug")
        let ios = try labels.create(name: "iOS")
        let project = try projects.create(name: "App")
        let task = try tasks.create(
            in: project,
            title: "Crash on launch",
            labelIDs: [bug.id, ios.id]
        )

        var snap = SearchMapping.snapshot(projects: try projects.fetchAll(), query: "Bug", includeArchived: false)
        #expect(snap.tasks.map(\.id).contains(task.id))
        #expect(snap.tasks.filter { $0.id == task.id }.count == 1)

        try labels.remove(labelID: bug.id, from: task.id)
        snap = SearchMapping.snapshot(projects: try projects.fetchAll(), query: "Bug", includeArchived: false)
        #expect(snap.tasks.map(\.id).contains(task.id) == false)

        snap = SearchMapping.snapshot(projects: try projects.fetchAll(), query: "iOS", includeArchived: false)
        #expect(snap.tasks.map(\.id).contains(task.id))

        try labels.delete(labelID: ios.id)
        snap = SearchMapping.snapshot(projects: try projects.fetchAll(), query: "iOS", includeArchived: false)
        #expect(snap.tasks.map(\.id).contains(task.id) == false)
    }

    // MARK: - Classifiers

    @Test("Label-only events skip widgets and notification reconcile")
    func classifiers() {
        #expect(WidgetReloadClassifier.kinds(for: .taskLabelsChanged).isEmpty)
        #expect(WidgetReloadClassifier.kinds(for: .labelDeleted).isEmpty)
        #expect(WidgetReloadClassifier.kinds(for: .labelContentChanged).isEmpty)
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .taskLabelsChanged) == false)
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .labelDeleted) == false)
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .taskReminderChanged))
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .taskCreated))
    }

    @Test("Label list ordering by localized name")
    func ordering() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let labels = LabelRepository(context: context)
        _ = try labels.create(name: "Zeta")
        _ = try labels.create(name: "Alpha")
        _ = try labels.create(name: "Middle")
        #expect(try labels.fetchAll().map(\.name) == ["Alpha", "Middle", "Zeta"])
    }
}
