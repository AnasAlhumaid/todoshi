import Foundation
import SwiftData
import Testing
@testable import TodoshiCore

@MainActor
struct PhaseProjectColumnsTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeContainer(kind: .inMemory))
    }

    private func customColumns() -> [ProjectColumn] {
        [
            ProjectColumn(name: "Ideas", colorHex: "#5248D9", kind: .todo),
            ProjectColumn(name: "Design", colorHex: "#E8920C", kind: .doing),
            ProjectColumn(name: "Client review", colorHex: "#8E5BD9", kind: .doing),
            ProjectColumn(name: "Shipped", colorHex: "#30A46C", kind: .done),
        ]
    }

    @Test("Projects without custom columns use the three defaults")
    func defaultsWhenUnset() throws {
        let context = try makeContext()
        let project = try ProjectRepository(context: context).create(name: "Board")
        let columns = ProjectColumnsPolicy.columns(for: project)
        #expect(columns.map(\.kind) == [.todo, .doing, .done])
        #expect(columns.map(\.id) == [
            ProjectColumnsPolicy.defaultTodoID,
            ProjectColumnsPolicy.defaultDoingID,
            ProjectColumnsPolicy.defaultDoneID,
        ])
    }

    @Test("Custom columns round-trip through the project")
    func customRoundTrip() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let project = try projects.create(name: "Board")
        let columns = customColumns()
        try projects.updateColumns(columns, for: project)
        #expect(ProjectColumnsPolicy.columns(for: project) == columns)
    }

    @Test("Validation requires a column of every kind and non-empty names")
    func validation() {
        var columns = customColumns()
        columns.removeAll { $0.kind == .done }
        #expect(throws: ProjectColumnsValidationError.missingKind(.done)) {
            try ProjectColumnsPolicy.validate(columns)
        }
        var unnamed = customColumns()
        unnamed[0].name = "  "
        #expect(throws: ProjectColumnsValidationError.emptyName) {
            try ProjectColumnsPolicy.validate(unnamed)
        }
    }

    @Test("Moving between columns of the same kind keeps the stored status")
    func sameKindMoveKeepsStatus() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Board")
        let columns = customColumns()
        try projects.updateColumns(columns, for: project)
        let task = try tasks.create(in: project, title: "Logo", status: .review)

        try tasks.move(taskID: task.id, toColumn: columns[1])
        #expect(task.status == .review)
        #expect(task.columnIDRaw == columns[1].id.uuidString)

        let resolved = ProjectColumnsPolicy.column(
            forColumnID: columns[1].id, status: task.status, in: columns
        )
        #expect(resolved == columns[1])
    }

    @Test("Moving into a column of another kind updates status and completion")
    func crossKindMoveUpdatesStatus() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Board")
        let columns = customColumns()
        try projects.updateColumns(columns, for: project)
        let task = try tasks.create(in: project, title: "Logo")

        try tasks.move(taskID: task.id, toColumn: columns[3])
        #expect(task.status == .done)
        #expect(task.completedAt != nil)
    }

    @Test("A stale column falls back to the first column of the task's kind")
    func staleColumnFallsBack() {
        let columns = customColumns()
        // Task was in "Client review" (doing) but got completed from Home.
        let resolved = ProjectColumnsPolicy.column(forColumnID: columns[2].id, status: .done, in: columns)
        #expect(resolved == columns[3])
        let missing = ProjectColumnsPolicy.column(forColumnID: UUID(), status: .inProgress, in: columns)
        #expect(missing == columns[1])
    }

    @Test("Removing a column reassigns its tasks to a same-kind column without status changes")
    func removalReassigns() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Board")
        var columns = customColumns()
        try projects.updateColumns(columns, for: project)
        let task = try tasks.create(in: project, title: "Logo", status: .inProgress)
        try tasks.move(taskID: task.id, toColumn: columns[2])

        let removed = columns.remove(at: 2)
        try projects.updateColumns(columns, for: project, reassignments: [removed.id: columns[1].id])
        #expect(task.columnIDRaw == columns[1].id.uuidString)
        #expect(task.status == .inProgress)
    }

    @Test("Checklist projects ignore custom columns")
    func unsupportedProjects() throws {
        let context = try makeContext()
        let projects = ProjectRepository(context: context)
        let checklist = try projects.create(name: "Groceries")
        checklist.projectType = .checklist
        checklist.columnsJSON = ProjectColumnsPolicy.encode(customColumns())
        #expect(ProjectColumnsPolicy.columns(for: checklist).map(\.id).first == ProjectColumnsPolicy.defaultTodoID)
    }
}
