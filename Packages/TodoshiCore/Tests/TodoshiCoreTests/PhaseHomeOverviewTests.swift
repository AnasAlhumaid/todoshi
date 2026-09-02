import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
struct PhaseHomeOverviewTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeContainer(kind: .inMemory))
    }

    @Test("Home mapping includes active projects only, ordered by position")
    func activeProjectOrdering() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let first = try projects.create(name: "Alpha")
        let second = try projects.create(name: "Beta")
        let archived = try projects.create(name: "Archived")
        try projects.archive(archived)

        let summaries = HomeMapping.projectSummaries(from: try projects.fetchAll())
        #expect(summaries.map(\.name) == ["Alpha", "Beta"])
        #expect(summaries.contains(where: { $0.id == archived.id }) == false)
        _ = (first, second)
    }

    @Test("Home mapping keeps empty active projects visible")
    func emptyActiveProjectVisible() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        _ = try projects.create(name: "Quiet")
        let summaries = HomeMapping.projectSummaries(from: try projects.fetchAll())
        #expect(summaries.count == 1)
        #expect(summaries[0].openTaskCount == 0)
        #expect(summaries[0].tasks.isEmpty)
    }

    @Test("Home tasks are open root tasks only")
    func openRootTasksOnly() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "P")
        let rootOpen = try tasks.create(in: project, title: "Root Open", status: .todo)
        let rootDone = try tasks.create(in: project, title: "Root Done", status: .done)
        _ = try tasks.createSubtask(parentTaskID: rootOpen.id, title: "Sub")

        let summary = HomeMapping.projectSummaries(from: [project]).first!
        #expect(summary.tasks.count == 1)
        #expect(summary.tasks[0].id == rootOpen.id)
        #expect(summary.tasks.contains(where: { $0.id == rootDone.id }) == false)
    }

    @Test("Home task ordering uses status precedence then position")
    func taskOrdering() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "P")

        _ = try tasks.create(in: project, title: "Backlog", status: .backlog)
        _ = try tasks.create(in: project, title: "Todo", status: .todo)
        _ = try tasks.create(in: project, title: "Review", status: .review)
        _ = try tasks.create(in: project, title: "Doing", status: .inProgress)

        let ordered = HomeMapping.projectSummaries(from: [project]).first!.tasks.map(\.title)
        #expect(ordered == ["Doing", "Review", "Todo", "Backlog"])
        #expect(HomeTaskOrdering.statusPrecedence == [.inProgress, .review, .todo, .backlog])

        let sameStatusA = try tasks.create(in: project, title: "A", status: .todo)
        let sameStatusB = try tasks.create(in: project, title: "B", status: .todo)
        _ = try tasks.move(taskID: sameStatusB.id, to: .todo, before: sameStatusA.id)

        let todoOrdered = HomeMapping.projectSummaries(from: [project]).first!
            .tasks
            .filter { $0.title == "A" || $0.title == "B" }
            .map(\.title)
        #expect(todoOrdered == ["B", "A"])
    }

    @Test("Home mapping does not duplicate tasks across projects")
    func noDuplicateTasksAcrossProjects() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let one = try projects.create(name: "One")
        let two = try projects.create(name: "Two")
        _ = try tasks.create(in: one, title: "T1", status: .todo)
        _ = try tasks.create(in: two, title: "T2", status: .review)

        let summaries = HomeMapping.projectSummaries(from: try projects.fetchAll())
        let allTaskIDs = summaries.flatMap(\.tasks).map(\.id)
        #expect(Set(allTaskIDs).count == allTaskIDs.count)
        #expect(allTaskIDs.count == 2)
    }

    @Test("Home task summaries preserve status identity for presentation")
    func statusPresentationIdentity() {
        let task = HomeTaskSummary(
            id: UUID(),
            projectID: UUID(),
            title: "Ship",
            status: .inProgress,
            priority: .medium,
            dueDate: nil,
            position: 1,
            createdAt: .now
        )
        #expect(task.status == .inProgress)
        #expect(task.accessibilityLabel(locale: Locale(identifier: "ar")).contains("قيد التنفيذ"))
    }

    @Test("Home mapping scales for many projects and tasks")
    func mappingPerformance() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)

        for index in 0..<20 {
            let project = try projects.create(name: "Project \(index)")
            for taskIndex in 0..<50 {
                let status: TaskStatus = switch taskIndex % 4 {
                case 0: .inProgress
                case 1: .review
                case 2: .todo
                default: .backlog
                }
                _ = try tasks.create(in: project, title: "Task \(taskIndex)", status: status)
            }
            _ = try tasks.create(in: project, title: "Done", status: .done)
        }

        let allProjects = try projects.fetchAll()
        let summaries = HomeMapping.projectSummaries(from: allProjects)
        #expect(summaries.count == 20)
        #expect(summaries.reduce(0) { $0 + $1.tasks.count } == 20 * 50)
    }
}
