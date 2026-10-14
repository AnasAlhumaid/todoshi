import Foundation
import SwiftData
import Testing
@testable import TodoshiCore

@MainActor
struct Phase8ProjectTypeTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeContainer(kind: .inMemory)
    }

    @Test("Schema V9 is current; projectTypeRaw remains additive")
    func schemaCurrent() {
        #expect(TodoshiSchema.currentVersion == TodoshiSchemaV9.versionIdentifier)
        #expect(TodoshiSchemaV9.versionIdentifier == Schema.Version(9, 0, 0))
        #expect(TodoshiSchemaMigrationPlan.stages.isEmpty)
    }

    @Test("Legacy Project defaults to Tasks")
    func legacyDefaultsToTasks() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "Legacy")
        #expect(project.projectTypeRaw == ProjectType.tasks.rawValue)
        project.projectTypeRaw = nil
        #expect(project.projectType == .tasks)
        #expect(ProjectType.resolve(nil) == .tasks)
        #expect(ProjectType.resolve("bogus") == .tasks)
    }

    @Test("ProjectType raw-value mapping")
    func rawMapping() {
        #expect(ProjectType(rawValue: "tasks") == .tasks)
        #expect(ProjectType(rawValue: "checklist") == .checklist)
        #expect(ProjectType.resolve("checklist") == .checklist)
    }

    @Test("Tasks and Checklist allowed statuses")
    func allowedStatuses() {
        #expect(ProjectTypeCapabilities.allowedStatuses(for: .tasks) == Array(TaskStatus.allCases))
        #expect(ProjectTypeCapabilities.allowedStatuses(for: .checklist) == [.todo, .inProgress, .done])
        #expect(ProjectTypeCapabilities.allowsStatus(.backlog, for: .tasks))
        #expect(ProjectTypeCapabilities.allowsStatus(.review, for: .tasks))
        #expect(!ProjectTypeCapabilities.allowsStatus(.backlog, for: .checklist))
        #expect(!ProjectTypeCapabilities.allowsStatus(.review, for: .checklist))
    }

    @Test("Checklist item defaults Todo and is a root TaskItem")
    func checklistDefaults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(
            name: "Shopping",
            projectType: .checklist
        )
        #expect(project.projectType == .checklist)
        #expect(project.icon == "checklist")

        let item = try TaskRepository(context: context).create(
            in: project,
            title: "Milk",
            status: ProjectTypeCapabilities.defaultStatus(for: .checklist)
        )
        #expect(item.isRoot)
        #expect(item.status == .todo)
        #expect(item.parentTask == nil)
    }

    @Test("Checklist rejects Backlog and Review through repository")
    func checklistRejectsInvalidStatus() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "List", projectType: .checklist)
        #expect(throws: RepositoryValidationError.invalidTaskStatusForProjectType) {
            _ = try TaskRepository(context: context).create(in: project, title: "X", status: .backlog)
        }
        #expect(throws: RepositoryValidationError.invalidTaskStatusForProjectType) {
            _ = try TaskRepository(context: context).create(in: project, title: "Y", status: .review)
        }
    }

    @Test("Checklist does not support subtasks; Tasks still does")
    func subtaskCapability() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TaskRepository(context: context)

        let checklist = try ProjectRepository(context: context).create(name: "CL", projectType: .checklist)
        let checklistRoot = try repo.create(in: checklist, title: "Root")
        #expect(!ProjectTypeCapabilities.supportsSubtasks(.checklist))
        #expect(throws: RepositoryValidationError.subtasksNotSupportedForProjectType) {
            _ = try repo.createSubtask(parentTaskID: checklistRoot.id, title: "Child")
        }

        let tasks = try ProjectRepository(context: context).create(name: "Tasks", projectType: .tasks)
        let tasksRoot = try repo.create(in: tasks, title: "Root")
        let child = try repo.createSubtask(parentTaskID: tasksRoot.id, title: "Child")
        #expect(!child.isRoot)
        #expect(ProjectTypeCapabilities.supportsSubtasks(.tasks))
        #expect(ProjectTypeCapabilities.supportsBoard(.tasks))
        #expect(!ProjectTypeCapabilities.supportsBoard(.checklist))
        #expect(ProjectTypeCapabilities.supportsNestedChecklist(.tasks))
        #expect(!ProjectTypeCapabilities.supportsNestedChecklist(.checklist))
    }

    @Test("Checklist assignee round-trip and My Items filtering")
    func assignmentAndFilter() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TaskRepository(context: context)
        let project = try ProjectRepository(context: context).create(name: "CL", projectType: .checklist)
        let mine = try repo.create(in: project, title: "Mine")
        let theirs = try repo.create(in: project, title: "Theirs")
        mine.assigneeUID = "me"
        theirs.assigneeUID = "them"

        let dto = try #require(FirestoreTaskMapping.dto(from: mine))
        #expect(dto.assigneeUID == "me")

        let filtered = TaskAssignmentFilter.mine.apply(to: [mine, theirs], viewerUID: "me")
        #expect(filtered.map(\.id) == [mine.id])
        #expect(TaskAssignmentFilter.mine.title(for: .checklist) == ProjectTerminologyPolicy.mineFilter(.checklist))
        #expect(TaskAssignmentFilter.all.title(for: .checklist) == ProjectTerminologyPolicy.allFilter(.checklist))
    }

    @Test("Checklist member progress counts only three statuses")
    func checklistProgress() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TaskRepository(context: context)
        let project = try ProjectRepository(context: context).create(name: "CL", projectType: .checklist)

        let a = try repo.create(in: project, title: "A", status: .todo)
        let b = try repo.create(in: project, title: "B", status: .inProgress)
        let c = try repo.create(in: project, title: "C", status: .done)
        for task in [a, b, c] { task.assigneeUID = "member-b" }

        // Done remains assigned.
        #expect(c.assigneeUID == "member-b")

        let progress = MemberAssignmentProgressPolicy.progress(
            for: "member-b",
            in: [a, b, c],
            projectType: .checklist
        )
        #expect(progress.total == 3)
        #expect(progress.count(for: .todo) == 1)
        #expect(progress.count(for: .inProgress) == 1)
        #expect(progress.count(for: .done) == 1)
        #expect(progress.count(for: .backlog) == 0)
        #expect(progress.count(for: .review) == 0)
    }

    @Test("Personal Checklist remains local (personal sharing mode)")
    func personalChecklistLocal() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "Home", projectType: .checklist)
        #expect(project.sharingMode == .personal)
        #expect(!project.isShared)
        #expect(project.remoteProjectID == nil)
    }

    @Test("Shared Checklist DTO projectType round-trip")
    func sharedChecklistDTO() {
        let dto = FirebaseProjectDTO(
            id: UUID(),
            ownerId: "owner",
            title: "Travel",
            description: "",
            color: "#5B8DEF",
            position: 1,
            memberIds: ["owner"],
            createdAt: .now,
            updatedAt: .now,
            projectTypeRaw: "checklist"
        )
        #expect(dto.resolvedProjectType == .checklist)

        let legacy = FirebaseProjectDTO(
            id: UUID(),
            ownerId: "owner",
            title: "Old",
            description: "",
            color: "#5B8DEF",
            position: 1,
            memberIds: ["owner"],
            createdAt: .now,
            updatedAt: .now
        )
        #expect(legacy.resolvedProjectType == .tasks)
    }

    @Test("ProjectType is immutable after creation")
    func immutableType() {
        #expect(!ProjectTypeCapabilities.canChangeType(from: .tasks, to: .checklist))
        #expect(!ProjectTypeCapabilities.canChangeType(from: .checklist, to: .tasks))
        #expect(ProjectTypeCapabilities.canChangeType(from: .tasks, to: .tasks))
    }

    @Test("Checklist restricted edit policy reuses ACL; feedback terminology differs")
    func checklistPermissionFeedback() {
        let restricted = AssignmentCandidate(uid: "r", role: .member, accessLevel: .restricted)
        #expect(
            !SharedTaskEditAuthorization.canEditTaskContent(
                role: restricted.role,
                accessLevel: restricted.resolvedAccessLevel,
                viewerUID: "r",
                rootEditorUIDs: []
            )
        )
        #expect(
            SharedTaskEditAuthorization.canEditTaskContent(
                role: restricted.role,
                accessLevel: restricted.resolvedAccessLevel,
                viewerUID: "r",
                rootEditorUIDs: ["r"]
            )
        )

        let feedback = SharedTaskPermissionFeedback.forEditAttempt(
            canEditTaskContent: false,
            projectType: .checklist
        )
        #expect(feedback == .deniedEdit(.checklist))
        #expect(feedback.toastMessage == ProjectTerminologyPolicy.noEditPermission(for: .checklist))
        #expect(
            ProjectTerminologyPolicy.noEditPermission(for: .tasks)
                == SharedTaskPermissionPresentation.noEditPermission
        )
    }

    @Test("Recurrence successor remains a valid Checklist root")
    func recurrenceChecklistSuccessor() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TaskRepository(context: context)
        let project = try ProjectRepository(context: context).create(name: "CL", projectType: .checklist)
        let task = try repo.create(
            in: project,
            title: "Weekly milk",
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            recurrenceRule: TaskRecurrenceRule(kind: .weekly)
        )
        task.assigneeUID = "member-b"
        task.editorUIDs = ["member-b"]

        try repo.complete(task, at: Date(timeIntervalSince1970: 1_800_003_600))
        let successorID = try #require(task.nextOccurrenceID)
        let successor = try #require(try repo.fetchTask(id: successorID))
        #expect(successor.isRoot)
        #expect(successor.parentTask == nil)
        #expect(ProjectTypeCapabilities.allowsStatus(successor.status, for: .checklist))
        #expect(successor.assigneeUID == "member-b")
        #expect(successor.editorUIDs == ["member-b"])
    }

    @Test("Account isolation for My Items unchanged")
    func accountIsolation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "CL", projectType: .checklist)
        let task = try TaskRepository(context: context).create(in: project, title: "Item")
        task.assigneeUID = "previous"
        #expect(TaskAssignmentFilter.mine.apply(to: [task], viewerUID: nil).isEmpty)
        #expect(TaskAssignmentFilter.mine.apply(to: [task], viewerUID: "new").isEmpty)
    }

    @Test("Checklist list mapping groups In Progress above Not Started; completed separate")
    func checklistMapping() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TaskRepository(context: context)
        let project = try ProjectRepository(context: context).create(name: "CL", projectType: .checklist)
        let todo = try repo.create(in: project, title: "Todo")
        let doing = try repo.create(in: project, title: "Doing", status: .inProgress)
        let done = try repo.create(in: project, title: "Done", status: .done)

        let snapshot = ChecklistProjectMapping.snapshot(from: project)
        #expect(snapshot.activeItems.map(\.id) == [doing.id, todo.id])
        #expect(snapshot.completedItems.map(\.id) == [done.id])
        #expect(snapshot.remainingCount == 1)
        #expect(snapshot.inProgressCount == 1)
        #expect(snapshot.completedCount == 1)
    }

    @Test("Existing Tasks project mappings unchanged")
    func tasksBoardUnchanged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "Board", projectType: .tasks)
        _ = try TaskRepository(context: context).create(in: project, title: "A", status: .backlog)
        _ = try TaskRepository(context: context).create(in: project, title: "B", status: .review)
        let board = ProjectBoardMapping.snapshot(from: project)
        #expect(board.sections.count == TaskStatus.allCases.count)
        #expect(board.sections.first { $0.status == .backlog }?.tasks.count == 1)
        #expect(board.sections.first { $0.status == .review }?.tasks.count == 1)
    }

    @Test("Checklist status cycle does not auto-reopen Done")
    func checklistCycle() {
        #expect(ProjectStatusPolicy.nextChecklistCycle(from: .todo) == .inProgress)
        #expect(ProjectStatusPolicy.nextChecklistCycle(from: .inProgress) == .done)
        #expect(ProjectStatusPolicy.nextChecklistCycle(from: .done) == nil)
    }
}
