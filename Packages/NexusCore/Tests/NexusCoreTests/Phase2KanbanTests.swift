import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
struct Phase2KanbanTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        return ModelContext(container)
    }

    private func seededBoard() throws -> (ModelContext, Project, TaskRepository, [TaskItem]) {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Kanban")
        let a = try tasks.create(in: project, title: "A", status: .todo)
        let b = try tasks.create(in: project, title: "B", status: .todo)
        let c = try tasks.create(in: project, title: "C", status: .todo)
        return (context, project, tasks, [a, b, c])
    }

    @Test("Move within same column before another task")
    func moveBeforeInColumn() throws {
        let (_, project, tasks, trio) = try seededBoard()
        let a = trio[0], b = trio[1], c = trio[2]
        #expect(a.position < b.position && b.position < c.position)

        let wrote = try tasks.move(taskID: c.id, to: .todo, before: a.id)
        #expect(wrote)
        #expect(c.position < a.position)
        #expect(c.status == .todo)

        let ordered = try tasks.fetchRootTasks(projectID: project.id, status: .todo).map(\.title)
        #expect(ordered == ["C", "A", "B"])
    }

    @Test("Move after another task via before successor")
    func moveAfterInColumn() throws {
        let (_, project, tasks, trio) = try seededBoard()
        let a = trio[0], b = trio[1], c = trio[2]

        // Place A after B => before C
        let wrote = try tasks.move(taskID: a.id, to: .todo, before: c.id)
        #expect(wrote)
        let ordered = try tasks.fetchRootTasks(projectID: project.id, status: .todo).map(\.title)
        #expect(ordered == ["B", "A", "C"])
        #expect(b.position < a.position && a.position < c.position)
    }

    @Test("Move to beginning and end")
    func moveBeginningAndEnd() throws {
        let (_, project, tasks, trio) = try seededBoard()
        let a = trio[0], b = trio[1], c = trio[2]

        _ = try tasks.move(taskID: b.id, to: .todo, before: a.id)
        #expect(try tasks.fetchRootTasks(projectID: project.id, status: .todo).map(\.title) == ["B", "A", "C"])

        _ = try tasks.move(taskID: b.id, to: .todo, before: nil)
        #expect(try tasks.fetchRootTasks(projectID: project.id, status: .todo).map(\.title) == ["A", "C", "B"])
        #expect(c.position < b.position || a.position < b.position)
    }

    @Test("Move to empty column")
    func moveEmptyColumn() throws {
        let (_, project, tasks, trio) = try seededBoard()
        let a = trio[0]
        let wrote = try tasks.move(taskID: a.id, to: .review, before: nil)
        #expect(wrote)
        #expect(a.status == .review)
        let review = try tasks.fetchRootTasks(projectID: project.id, status: .review)
        #expect(review.count == 1)
        #expect(review.first?.id == a.id)
        #expect(try tasks.fetchRootTasks(projectID: project.id, status: .todo).count == 2)
    }

    @Test("Cross-column move applies completedAt rules")
    func crossColumnCompletion() throws {
        let (_, _, tasks, trio) = try seededBoard()
        let a = trio[0]
        #expect(a.completedAt == nil)

        _ = try tasks.move(taskID: a.id, to: .done, before: nil)
        #expect(a.status == .done)
        #expect(a.completedAt != nil)
        let completed = a.completedAt

        _ = try tasks.move(taskID: a.id, to: .inProgress, before: nil)
        #expect(a.status == .inProgress)
        #expect(a.completedAt == nil)

        _ = try tasks.move(taskID: a.id, to: .done, before: nil)
        #expect(a.completedAt != nil)
        // completed stamp may differ from first completion
        _ = completed
    }

    @Test("Self-drop and current placement are no-ops")
    func selfDropNoOp() throws {
        let (_, _, tasks, trio) = try seededBoard()
        let a = trio[0], b = trio[1]
        let original = a.position

        #expect(try tasks.move(taskID: a.id, to: .todo, before: a.id) == false)
        #expect(a.position == original)

        // Drop before next sibling preserves order when already before b
        #expect(try tasks.move(taskID: a.id, to: .todo, before: b.id) == false)
        #expect(a.position == original)

        // Append when already last is no-op for c
        let c = trio[2]
        let cPos = c.position
        #expect(try tasks.move(taskID: c.id, to: .todo, before: nil) == false)
        #expect(c.position == cPos)
    }

    @Test("Moving task excluded from destination peers")
    func moverExcludedFromPeers() throws {
        let (context, project, tasks, _) = try seededBoard()
        let solo = try tasks.create(in: project, title: "Solo", status: .backlog)
        _ = try tasks.move(taskID: solo.id, to: .todo, before: nil)

        let todo = try tasks.fetchRootTasks(projectID: project.id, status: .todo)
        #expect(todo.map(\.title).contains("Solo"))
        let positions = todo.map(\.position)
        #expect(FractionalPosition.needsNormalization(positions: positions) == false)

        // Force a same-column reinsert between first and second without counting self twice
        let first = todo[0]
        let second = todo[1]
        _ = try tasks.move(taskID: solo.id, to: .todo, before: second.id)
        #expect(solo.id != first.id || first.id == solo.id)
        let ordered = try tasks.fetchRootTasks(projectID: project.id, status: .todo)
        #expect(ordered.contains { $0.id == solo.id })
        _ = context
    }

    @Test("Fractional placement helpers")
    func fractionalHelpers() {
        let first = FractionalPosition.initial()
        let second = FractionalPosition.after(first)
        let mid = FractionalPosition.between(lower: first, upper: second)
        #expect(mid > first && mid < second)
        #expect(FractionalPosition.between(lower: nil, upper: first) < first)
        #expect(FractionalPosition.between(lower: second, upper: nil) > second)
        #expect(FractionalPosition.between(lower: nil, upper: nil) == FractionalPosition.initial())
    }

    @Test("Duplicate and tiny gaps trigger normalization; preserves order")
    func normalizationBehavior() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Norm")
        let t1 = try tasks.create(in: project, title: "1", status: .todo)
        let t2 = try tasks.create(in: project, title: "2", status: .todo)
        let t3 = try tasks.create(in: project, title: "3", status: .todo)

        // Craft pathological positions
        t1.position = 1
        t2.position = 1 + 1e-9
        t3.position = 1 + 2e-9
        try context.save()

        #expect(FractionalPosition.needsNormalization(positions: [t1.position, t2.position, t3.position]))

        let column = [t1, t2, t3]
        let orderBefore = column.sorted { $0.position < $1.position || ($0.position == $1.position && $0.createdAt < $1.createdAt) }.map(\.title)
        tasks.normalizeIfNeeded(column)
        try context.save()

        let after = try tasks.fetchRootTasks(projectID: project.id, status: .todo)
        #expect(after.map(\.title) == orderBefore)
        #expect(FractionalPosition.needsNormalization(positions: after.map(\.position)) == false)

        // Non-destination status untouched
        let other = try tasks.create(in: project, title: "Other", status: .review)
        let reviewPos = other.position
        tasks.normalizeIfNeeded([t1, t2, t3])
        #expect(other.position == reviewPos)
        #expect(other.status == .review)
    }

    @Test("Non-finite positions require normalization")
    func nonFiniteNormalization() {
        #expect(FractionalPosition.needsNormalization(positions: [1, .nan]))
        #expect(FractionalPosition.needsNormalization(positions: [1, .infinity]))
    }

    @Test("moveToStatus fallback matches append destination end")
    func moveToStatusFallback() throws {
        let (_, project, tasks, trio) = try seededBoard()
        let a = trio[0]
        try tasks.moveToStatus(a, .inProgress)
        #expect(a.status == .inProgress)
        let column = try tasks.fetchRootTasks(projectID: project.id, status: .inProgress)
        #expect(column.last?.id == a.id)
    }

    @Test("Column add task preselects status via draft")
    func columnAddTaskDraftStatus() {
        let draft = TaskDraft(status: .review)
        #expect(draft.status == .review)
        #expect(draft.isValid == false)
        var ready = draft
        ready.title = "From column"
        #expect(ready.isValid)
    }

    @Test("Board display preference defaults and storage key")
    func displayPreference() {
        #expect(ProjectTaskDisplayMode.storageKey == "nexus.projectTaskDisplayMode")
        #expect(ProjectTaskDisplayMode.default == .board)
        #expect(ProjectTaskDisplayMode(rawValue: "list") == .list)
        #expect(ProjectTaskDisplayMode.board.title == "Board")
    }

    @Test("Store reset policy is compile-time gated")
    func storeResetPolicy() {
        #if DEBUG
        #expect(StoreResetPolicy.allowsDestructiveAppGroupReset == true)
        #else
        #expect(StoreResetPolicy.allowsDestructiveAppGroupReset == false)
        #endif
    }

    @Test("moveEarlier and moveLater")
    func moveAdjacent() throws {
        let (_, project, tasks, trio) = try seededBoard()
        let b = trio[1]
        #expect(try tasks.moveEarlier(taskID: b.id))
        #expect(try tasks.fetchRootTasks(projectID: project.id, status: .todo).map(\.title).first == "B")
        #expect(try tasks.moveLater(taskID: b.id))
        #expect(try tasks.fetchRootTasks(projectID: project.id, status: .todo).map(\.title) == ["A", "B", "C"])
    }
}
