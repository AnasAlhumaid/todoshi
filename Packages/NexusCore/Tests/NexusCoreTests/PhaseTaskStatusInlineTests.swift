import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
struct PhaseTaskStatusInlineTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeContainer(kind: .inMemory))
    }

    @Test("Todo to In Progress via repository move")
    func todoToInProgress() throws {
        let context = try makeContext()
        let project = try ProjectRepository(context: context).create(name: "P")
        let tasks = TaskRepository(context: context)
        let task = try tasks.create(in: project, title: "Work", status: .todo)

        let wrote = try tasks.move(taskID: task.id, to: .inProgress, before: nil)
        #expect(wrote)
        #expect(task.status == .inProgress)
        #expect(task.completedAt == nil)
    }

    @Test("In Progress to Review and Review to Done")
    func progressToDone() throws {
        let context = try makeContext()
        let project = try ProjectRepository(context: context).create(name: "P")
        let tasks = TaskRepository(context: context)
        let task = try tasks.create(in: project, title: "Work", status: .inProgress)

        _ = try tasks.move(taskID: task.id, to: .review, before: nil)
        #expect(task.status == .review)

        let doneAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try tasks.move(taskID: task.id, to: .done, before: nil, at: doneAt)
        #expect(task.status == .done)
        #expect(task.completedAt == doneAt)
    }

    @Test("Done to Todo clears completion and Backlog to Todo")
    func reopenAndBacklog() throws {
        let context = try makeContext()
        let project = try ProjectRepository(context: context).create(name: "P")
        let tasks = TaskRepository(context: context)

        let done = try tasks.create(in: project, title: "Done", status: .done)
        done.completedAt = .now
        _ = try tasks.move(taskID: done.id, to: .todo, before: nil)
        #expect(done.status == .todo)
        #expect(done.completedAt == nil)

        let backlog = try tasks.create(in: project, title: "Backlog", status: .backlog)
        _ = try tasks.move(taskID: backlog.id, to: .todo, before: nil)
        #expect(backlog.status == .todo)
    }

    @Test("Same-status append move is a no-op")
    func sameStatusNoOp() throws {
        let context = try makeContext()
        let project = try ProjectRepository(context: context).create(name: "P")
        let tasks = TaskRepository(context: context)
        let task = try tasks.create(in: project, title: "Stay", status: .todo)

        let wrote = try tasks.move(taskID: task.id, to: .todo, before: nil)
        #expect(wrote == false)
    }

    @Test("Move assigns destination section position and updates board snapshot")
    func boardSnapshotMovesSection() throws {
        let context = try makeContext()
        let project = try ProjectRepository(context: context).create(name: "P")
        let tasks = TaskRepository(context: context)
        let task = try tasks.create(in: project, title: "Move me", status: .todo)

        let before = ProjectBoardMapping.snapshot(from: project)
        #expect(before.section(for: .todo)?.tasks.map(\.id) == [task.id])
        #expect(before.section(for: .inProgress)?.tasks.isEmpty == true)

        _ = try tasks.move(taskID: task.id, to: .inProgress, before: nil)

        let after = ProjectBoardMapping.snapshot(from: project)
        #expect(after.section(for: .todo)?.tasks.isEmpty == true)
        #expect(after.section(for: .inProgress)?.tasks.map(\.id) == [task.id])
        #expect(after.section(for: .inProgress)?.tasks.first?.position == task.position)
    }

    @Test("Recurring root task moved to Done generates next occurrence")
    func recurrenceOnDone() throws {
        let context = try makeContext()
        let project = try ProjectRepository(context: context).create(name: "P")
        let tasks = TaskRepository(context: context)
        let due = Date(timeIntervalSince1970: 1_700_000_000)
        let task = try tasks.create(
            in: project,
            title: "Daily",
            dueDate: due,
            recurrenceRule: TaskRecurrenceRule(kind: .daily)
        )

        _ = try tasks.move(taskID: task.id, to: .done, before: nil, at: due)
        #expect(task.nextOccurrenceID != nil)
        let next = try tasks.fetchTask(id: task.nextOccurrenceID!)
        #expect(next?.status == .todo)
    }

    @Test("Status shortcuts map common transitions")
    func shortcuts() {
        #expect(TaskStatusShortcuts.primary(from: .todo)?.target == .inProgress)
        #expect(TaskStatusShortcuts.primary(from: .inProgress)?.target == .review)
        #expect(TaskStatusShortcuts.primary(from: .review)?.target == .done)
        #expect(TaskStatusShortcuts.primary(from: .done)?.target == .todo)
        #expect(TaskStatusShortcuts.primary(from: .backlog)?.target == .todo)

        let ar = Locale(identifier: "ar")
        #expect(TaskStatusShortcuts.primary(from: .todo)?.label(locale: ar) == "بدء العمل")
        #expect(TaskStatusShortcuts.primary(from: .review)?.label(locale: ar) == "إكمال المهمة")
    }

    @Test("Done and reopen moves classify widget reload and notification reconcile")
    func changeClassification() {
        #expect(WidgetReloadClassifier.kinds(for: .taskCompletedOrReopened).isEmpty == false)
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .taskCompletedOrReopened))
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .taskContentChanged))
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .recurringOccurrenceGenerated))
    }
}
