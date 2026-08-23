import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
struct PhaseProjectBoardTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeContainer(kind: .inMemory))
    }

    @Test("Project board includes all five workflow statuses in order")
    func allStatusesRepresented() throws {
        let context = try makeContext()
        let project = try ProjectRepository(context: context).create(name: "Board")
        let snapshot = ProjectBoardMapping.snapshot(from: project)

        #expect(snapshot.sections.map(\.status) == ProjectBoardSnapshot.workflowStatusOrder)
        #expect(snapshot.sections.count == 5)
    }

    @Test("Empty statuses remain available in project board")
    func emptyStatusesVisible() throws {
        let context = try makeContext()
        let project = try ProjectRepository(context: context).create(name: "Board")
        let snapshot = ProjectBoardMapping.snapshot(from: project)

        for section in snapshot.sections {
            #expect(section.count == 0)
            #expect(section.tasks.isEmpty)
        }
    }

    @Test("Done tasks appear only in completed section; subtasks excluded")
    func sectionMembership() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Board")

        let open = try tasks.create(in: project, title: "Open", status: .todo)
        let done = try tasks.create(in: project, title: "Done", status: .done)
        _ = try tasks.createSubtask(parentTaskID: open.id, title: "Child")

        let snapshot = ProjectBoardMapping.snapshot(from: project)
        let todoSection = snapshot.section(for: .todo)!
        let doneSection = snapshot.section(for: .done)!

        #expect(todoSection.tasks.map(\.id) == [open.id])
        #expect(doneSection.tasks.map(\.id) == [done.id])
        #expect(snapshot.sections.flatMap(\.tasks).count == 2)
    }

    @Test("Tasks order by position within each status section")
    func taskOrderingWithinStatus() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Board")

        let first = try tasks.create(in: project, title: "First", status: .todo)
        let second = try tasks.create(in: project, title: "Second", status: .todo)
        _ = try tasks.move(taskID: second.id, to: .todo, before: first.id)

        let ordered = ProjectBoardMapping.snapshot(from: project)
            .section(for: .todo)!
            .tasks
            .map(\.title)
        #expect(ordered == ["Second", "First"])
    }

    @Test("Project board snapshot maps one task per section without duplication")
    func noDuplicateTasks() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Board")

        _ = try tasks.create(in: project, title: "A", status: .backlog)
        _ = try tasks.create(in: project, title: "B", status: .inProgress)
        _ = try tasks.create(in: project, title: "C", status: .review)
        _ = try tasks.create(in: project, title: "D", status: .done)

        let snapshot = ProjectBoardMapping.snapshot(from: project)
        let allIDs = snapshot.sections.flatMap(\.tasks).map(\.id)
        #expect(Set(allIDs).count == allIDs.count)
        #expect(allIDs.count == 4)
    }

    @Test("Done preview limit is defined for large completed sections")
    func donePreviewLimit() {
        #expect(ProjectBoardSnapshot.donePreviewLimit == 12)
    }
}
