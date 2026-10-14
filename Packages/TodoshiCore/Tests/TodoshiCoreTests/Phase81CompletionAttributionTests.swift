import Foundation
import SwiftData
import Testing
@testable import TodoshiCore

@MainActor
struct Phase81CompletionAttributionTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeContainer(kind: .inMemory)
    }

    @Test("Schema V9 adds completion attribution additively")
    func schemaV9() {
        #expect(TodoshiSchema.currentVersion == TodoshiSchemaV9.versionIdentifier)
        #expect(TodoshiSchemaV9.versionIdentifier == Schema.Version(9, 0, 0))
        #expect(TodoshiSchemaMigrationPlan.stages.isEmpty)
    }

    @Test("Existing task defaults completedBy to nil")
    func defaultsNil() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "P", projectType: .checklist)
        let item = try TaskRepository(context: context).create(in: project, title: "Milk")
        #expect(item.completedByUID == nil)
        #expect(item.completedByDisplayName == nil)
        #expect(item.completedAt == nil)
    }

    @Test("completedBy DTO round-trip")
    func dtoRoundTrip() throws {
        let id = UUID()
        let projectId = UUID()
        let dto = FirestoreTaskDTO(
            id: id,
            projectId: projectId,
            title: "Milk",
            statusRaw: TaskStatus.done.rawValue,
            priorityRaw: TaskPriority.none.rawValue,
            position: 1,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedByUID: "uid-a",
            completedByDisplayName: "Anas Hamad",
            createdAt: .now,
            updatedAt: .now
        )
        #expect(dto.completedByUID == "uid-a")
        #expect(dto.completedByDisplayName == "Anas Hamad")

        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "CL", projectType: .checklist)
        let task = try TaskRepository(context: context).create(in: project, title: "X")
        FirestoreTaskMapping.apply(dto, to: task)
        #expect(task.completedByUID == "uid-a")
        #expect(task.completedByDisplayName == "Anas Hamad")

        let mapped = FirestoreTaskMapping.dto(from: task)
        #expect(mapped?.completedByUID == "uid-a")
        #expect(mapped?.completedByDisplayName == "Anas Hamad")
    }

    @Test("Shared completion records current UID and display-name snapshot")
    func sharedCompletionRecordsActor() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "CL", projectType: .checklist)
        let item = try TaskRepository(context: context).create(in: project, title: "Milk")
        let actor = TaskCompletionActor(uid: "uid-anas", displayName: "Anas Hamad")
        try TaskRepository(context: context).complete(item, completionActor: actor)
        #expect(item.status == .done)
        #expect(item.completedByUID == "uid-anas")
        #expect(item.completedByDisplayName == "Anas Hamad")
        #expect(item.completedAt != nil)
    }

    @Test("Assignee and completer may differ")
    func assigneeIndependent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "CL", projectType: .checklist)
        let item = try TaskRepository(context: context).create(in: project, title: "Milk")
        item.assigneeUID = "uid-b"
        try context.save()
        try TaskRepository(context: context).complete(
            item,
            completionActor: TaskCompletionActor(uid: "uid-a", displayName: "Anas")
        )
        #expect(item.assigneeUID == "uid-b")
        #expect(item.completedByUID == "uid-a")
    }

    @Test("Reopen clears attribution")
    func reopenClears() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "CL", projectType: .checklist)
        let item = try TaskRepository(context: context).create(in: project, title: "Milk")
        try TaskRepository(context: context).complete(
            item,
            completionActor: TaskCompletionActor(uid: "uid-a", displayName: "Anas")
        )
        try TaskRepository(context: context).reopen(item)
        #expect(item.status == .todo)
        #expect(item.completedAt == nil)
        #expect(item.completedByUID == nil)
        #expect(item.completedByDisplayName == nil)
    }

    @Test("Re-complete replaces attribution with new actor")
    func recompleteReplaces() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "CL", projectType: .checklist)
        let item = try TaskRepository(context: context).create(in: project, title: "Milk")
        let repo = TaskRepository(context: context)
        try repo.complete(item, completionActor: TaskCompletionActor(uid: "uid-a", displayName: "Anas"))
        try repo.reopen(item)
        try repo.complete(item, completionActor: TaskCompletionActor(uid: "uid-m", displayName: "Mohammed"))
        #expect(item.completedByUID == "uid-m")
        #expect(item.completedByDisplayName == "Mohammed")
    }

    @Test("Done→Done edit preserves attribution")
    func doneEditPreserves() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "CL", projectType: .checklist)
        let item = try TaskRepository(context: context).create(in: project, title: "Milk")
        let repo = TaskRepository(context: context)
        try repo.complete(item, completionActor: TaskCompletionActor(uid: "uid-a", displayName: "Anas"))
        let stamp = item.completedAt
        try repo.update(
            item,
            title: "Milk 2%",
            taskDescription: item.taskDescription,
            status: .done,
            priority: item.priority,
            dueDate: item.dueDate,
            notes: "note",
            completionActor: TaskCompletionActor(uid: "uid-spoof", displayName: "Spoof")
        )
        #expect(item.title == "Milk 2%")
        #expect(item.completedByUID == "uid-a")
        #expect(item.completedByDisplayName == "Anas")
        #expect(item.completedAt == stamp)
    }

    @Test("Legacy Done without attribution remains valid")
    func legacyDone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "CL", projectType: .checklist)
        let item = try TaskRepository(context: context).create(in: project, title: "Old")
        item.status = .done
        item.completedAt = .now
        item.completedByUID = nil
        item.completedByDisplayName = nil
        try context.save()
        #expect(TaskCompletionPresentation.completedByLine(
            completedByUID: item.completedByUID,
            completedByDisplayName: item.completedByDisplayName
        ) == nil)
    }

    @Test("Personal Checklist does not require actor")
    func personalNoActor() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "Home", projectType: .checklist)
        #expect(project.sharingMode == .personal)
        let item = try TaskRepository(context: context).create(in: project, title: "Milk")
        try TaskRepository(context: context).complete(item, completionActor: nil)
        #expect(item.status == .done)
        #expect(item.completedByUID == nil)
        #expect(item.completedByDisplayName == nil)
        #expect(item.completedAt != nil)
    }

    @Test("Recurring successor clears completion attribution")
    func recurrenceSuccessorClears() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "CL", projectType: .checklist)
        let due = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 27))!
        let item = try TaskRepository(context: context).create(
            in: project,
            title: "Weekly",
            dueDate: due,
            recurrenceRule: TaskRecurrenceRule(kind: .daily)
        )
        try TaskRepository(context: context).complete(
            item,
            at: due,
            completionActor: TaskCompletionActor(uid: "uid-a", displayName: "Anas")
        )
        #expect(item.completedByUID == "uid-a")
        guard let nextID = item.nextOccurrenceID,
              let next = try TaskRepository(context: context).fetchTask(id: nextID)
        else {
            Issue.record("Expected successor")
            return
        }
        #expect(next.status != .done)
        #expect(next.completedAt == nil)
        #expect(next.completedByUID == nil)
        #expect(next.completedByDisplayName == nil)
        #expect(next.assigneeUID == item.assigneeUID)
    }

    @Test("Soft delete preserves historical attribution")
    func softDeletePreserves() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "CL", projectType: .checklist)
        project.sharingMode = .shared
        project.remoteProjectID = project.id.uuidString
        let item = try TaskRepository(context: context).create(in: project, title: "Milk")
        try TaskRepository(context: context).complete(
            item,
            completionActor: TaskCompletionActor(uid: "uid-a", displayName: "Anas")
        )
        try TaskRepository(context: context).delete(item, mode: .deleteDescendants)
        #expect(item.deletedAt != nil)
        #expect(item.completedByUID == "uid-a")
        #expect(item.completedByDisplayName == "Anas")
        #expect(TaskCompletionAttribution.shouldPreserveOnSoftDelete())
    }

    @Test("Checklist row presentation with and without attribution")
    func presentation() {
        let with = TaskCompletionPresentation.completedByLine(
            completedByUID: "uid-a",
            completedByDisplayName: "Anas Hamad"
        )
        #expect(with?.contains("Anas Hamad") == true)
        let without = TaskCompletionPresentation.completedByLine(
            completedByUID: nil,
            completedByDisplayName: nil
        )
        #expect(without == nil)
        #expect(!TaskCompletionPresentation.completedByLabel.isEmpty)
    }

    @Test("Account UID isolation — actor uses provided UID only")
    func accountIsolation() {
        let actor = TaskCompletionActor(uid: "uid-owner", displayName: "Owner")
        var completedAt: Date?
        var byUID: String?
        var byName: String?
        TaskCompletionAttribution.apply(
            from: .todo,
            to: .done,
            completedAt: &completedAt,
            completedByUID: &byUID,
            completedByDisplayName: &byName,
            actor: actor,
            at: .now
        )
        #expect(byUID == "uid-owner")
        #expect(byUID != "uid-other")
    }
}
