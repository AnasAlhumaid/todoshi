import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
struct PhaseTaskDetailSubtaskPresentationTests {
    @Test("Add Subtask action produces stable presentation context")
    func presentationContext() {
        let parentID = UUID()
        let projectID = UUID()
        let context = TaskSubtaskFormContext(parentTaskID: parentID, projectID: projectID)

        #expect(context.parentTaskID == parentID)
        #expect(context.projectID == projectID)
        #expect(context.id == "subtask-\(parentID.uuidString)")
    }

    @Test("Repeated presentation contexts are equal for the same parent")
    func repeatedPresentation() {
        let parentID = UUID()
        let projectID = UUID()
        let first = TaskSubtaskFormContext(parentTaskID: parentID, projectID: projectID)
        let second = TaskSubtaskFormContext(parentTaskID: parentID, projectID: projectID)

        #expect(first == second)
        #expect(first.id == second.id)
    }

    @Test("Successful subtask save creates exactly one child excluded from root queries")
    func saveCreatesOneChild() throws {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)

        let project = try projects.create(name: "P")
        let root = try tasks.create(in: project, title: "Root", status: .todo)

        let child = try tasks.createSubtask(parentTaskID: root.id, title: "Child")
        #expect(child.parentTask?.id == root.id)
        #expect(child.project?.id == project.id)

        let roots = try tasks.fetchRootTasks(projectID: project.id)
        #expect(roots.count == 1)
        #expect(roots.first?.id == root.id)
        #expect(roots.contains { $0.id == child.id } == false)
    }
}
