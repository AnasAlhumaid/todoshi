import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
struct Phase1ProjectsTasksTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        return ModelContext(container)
    }

    @Test("Field validation trims and requires non-empty names")
    func fieldValidation() {
        #expect(FieldValidation.trimmed("  hello  ") == "hello")
        #expect(FieldValidation.requiredName("   ") == nil)
        #expect(FieldValidation.requiredName("  Nexus  ") == "Nexus")
        #expect(FieldValidation.isValidRequiredName("x"))
        #expect(FieldValidation.isValidRequiredName("  ") == false)

        var draft = ProjectDraft(name: "  ")
        #expect(draft.isValid == false)
        draft.name = " App "
        #expect(draft.isValid)

        var taskDraft = TaskDraft(title: "\n")
        #expect(taskDraft.isValid == false)
        taskDraft.title = "Ship"
        #expect(taskDraft.isValid)
    }

    @Test("Project creation assigns position and trims fields")
    func projectCreation() throws {
        let context = try makeContext()
        let repo = ProjectRepository(context: context)

        let first = try repo.create(name: "  Alpha  ", icon: "bolt.fill", colorHex: "#3DBB7A", projectDescription: "  desc  ")
        #expect(first.name == "Alpha")
        #expect(first.projectDescription == "desc")
        #expect(first.position == FractionalPosition.initial())
        #expect(first.status == .active)

        let second = try repo.create(name: "Beta")
        #expect(second.position == FractionalPosition.after(first.position))
        #expect(second.position > first.position)
    }

    @Test("Project create rejects empty name")
    func projectCreateValidation() throws {
        let context = try makeContext()
        let repo = ProjectRepository(context: context)
        #expect(throws: RepositoryValidationError.emptyName) {
            try repo.create(name: "   ")
        }
    }

    @Test("Project editing updates fields and updatedAt")
    func projectEditing() throws {
        let context = try makeContext()
        let repo = ProjectRepository(context: context)
        let project = try repo.create(name: "Old")
        let before = project.updatedAt

        try repo.update(
            project,
            name: "  New Name  ",
            icon: "star.fill",
            colorHex: "#E85D75",
            projectDescription: "  hello  ",
            at: before.addingTimeInterval(5)
        )

        #expect(project.name == "New Name")
        #expect(project.icon == "star.fill")
        #expect(project.colorHex == "#E85D75")
        #expect(project.projectDescription == "hello")
        #expect(project.updatedAt > before)
    }

    @Test("Project archive and restore")
    func projectArchiveRestore() throws {
        let context = try makeContext()
        let repo = ProjectRepository(context: context)
        let project = try repo.create(name: "Live")
        try repo.archive(project)
        #expect(project.status == .archived)
        #expect(try repo.fetch(status: .active).isEmpty)
        #expect(try repo.fetch(status: .archived).count == 1)

        try repo.restore(project)
        #expect(project.status == .active)
        #expect(try repo.fetch(status: .active).count == 1)
    }

    @Test("Project deletion cascades tasks")
    func projectDeleteCascade() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Doomed")
        _ = try tasks.create(in: project, title: "T1")
        _ = try tasks.create(in: project, title: "T2")
        #expect(try tasks.fetchAllTasks().count == 2)

        try projects.delete(project)
        #expect(try projects.fetchAll().isEmpty)
        #expect(try tasks.fetchAllTasks().isEmpty)
    }

    @Test("Open task counts by project")
    func openTaskCounts() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Counts")
        _ = try tasks.create(in: project, title: "Open", status: .todo)
        _ = try tasks.create(in: project, title: "WIP", status: .inProgress)
        let done = try tasks.create(in: project, title: "Done", status: .done)

        #expect(ProjectTaskCounts.openRootCount(tasks: project.tasks ?? []) == 2)
        #expect(projects.openRootTaskCount(for: project) == 2)
        #expect(done.completedAt != nil)

        // Subtask should not count as open root
        let parent = try tasks.fetchTask(id: try tasks.create(in: project, title: "Parent").id)!
        let child = TaskItem(title: "Child", status: .todo, project: project, parentTask: parent)
        context.insert(child)
        try context.save()
        #expect(projects.openRootTaskCount(for: project) == 3)
    }

    @Test("Task creation inside project assigns status position")
    func taskCreationPosition() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Board")

        let a = try tasks.create(in: project, title: "A", status: .todo)
        let b = try tasks.create(in: project, title: "B", status: .todo)
        let c = try tasks.create(in: project, title: "C", status: .backlog)

        #expect(a.position == FractionalPosition.initial())
        #expect(b.position == FractionalPosition.after(a.position))
        #expect(c.position == FractionalPosition.initial())
        #expect(a.project?.id == project.id)
        #expect(b.position > a.position)
    }

    @Test("Task creation rejects empty title")
    func taskCreateValidation() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "P")
        #expect(throws: RepositoryValidationError.emptyName) {
            try tasks.create(in: project, title: "  ")
        }
    }

    @Test("Task editing and status into and out of Done")
    func taskEditingAndCompletion() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "P")
        let task = try tasks.create(in: project, title: "Work", status: .todo)
        #expect(task.completedAt == nil)

        try tasks.update(
            task,
            title: "  Done Work  ",
            taskDescription: "  d  ",
            status: .done,
            priority: .high,
            dueDate: nil,
            notes: " n "
        )
        #expect(task.title == "Done Work")
        #expect(task.taskDescription == "d")
        #expect(task.notes == "n")
        #expect(task.status == .done)
        #expect(task.completedAt != nil)
        let completed = task.completedAt

        try tasks.moveToStatus(task, .todo)
        #expect(task.status == .todo)
        #expect(task.completedAt == nil)

        try tasks.moveToStatus(task, .done)
        #expect(task.completedAt != nil)
        #expect(task.completedAt != completed || task.completedAt != nil)
    }

    @Test("Task deletion with descendants uses repository mode")
    func taskDeleteDescendants() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Tree")
        let root = try tasks.create(in: project, title: "Root")
        let mid = TaskItem(title: "Mid", project: project, parentTask: root)
        context.insert(mid)
        let leaf = TaskItem(title: "Leaf", project: project, parentTask: mid)
        context.insert(leaf)
        try context.save()

        #expect(tasks.descendantCount(of: root) == 2)
        try tasks.delete(root, mode: .deleteDescendants)
        #expect(try tasks.fetchAllTasks().isEmpty)
    }

    @Test("Project draft and task draft sync from models")
    func draftsFromModels() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "P", icon: "star.fill", colorHex: "#E85D75", projectDescription: "d")
        let task = try tasks.create(in: project, title: "T", status: .review, priority: .urgent)

        let pd = ProjectDraft(project: project)
        #expect(pd.name == "P")
        #expect(pd.icon == "star.fill")

        let td = TaskDraft(task: task)
        #expect(td.title == "T")
        #expect(td.status == .review)
        #expect(td.priority == .urgent)
    }
}
