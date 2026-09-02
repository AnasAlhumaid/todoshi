import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
struct Phase10ResourcesTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeContainer(kind: .inMemory)
    }

    private func makeFileStore() throws -> TaskResourceFileStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusResourceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let store = TaskResourceFileStore(rootURL: url)
        TaskResourceFileAccess.current = store
        return store
    }

    private func seedTask(_ context: ModelContext) throws -> (Project, TaskItem) {
        let projects = ProjectRepository(context: context)
        let tasks = TaskRepository(context: context)
        let project = try projects.create(name: "Res")
        let task = try tasks.create(in: project, title: "Owner")
        return (project, task)
    }

    private func writeTempFile(data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Schema

    @Test("Schema V4 includes TaskResource; current version is V4")
    func schemaIdentity() {
        #expect(NexusSchema.currentVersion == NexusSchemaV4.versionIdentifier)
        #expect(NexusSchema.currentModels.contains { $0 == TaskResource.self })
        #expect(StoreResetPolicy.allowsDestructiveAppGroupReset == {
            #if DEBUG
            true
            #else
            false
            #endif
        }())
    }

    // MARK: - Validation

    @Test("Resource validation: URLs, empty bodies, title/body length, whitespace preserved")
    func validation() {
        #expect(TaskResourceValidation.issueForLink(title: "", urlString: "https://example.com") == nil)
        #expect(TaskResourceValidation.issueForLink(title: "", urlString: "http://example.com") == nil)
        #expect(TaskResourceValidation.issueForLink(title: "", urlString: "not a url") == .invalidURL)
        #expect(TaskResourceValidation.issueForLink(title: "", urlString: "javascript:alert(1)") == .unsupportedURLScheme)
        #expect(TaskResourceValidation.issueForTextBody(title: "", body: "") == .emptyBody)
        #expect(TaskResourceValidation.issueForTextBody(title: "", body: "  ") == .emptyBody)
        let code = "func x() {\n  return 1\n}"
        #expect(TaskResourceValidation.issueForTextBody(title: "", body: code) == nil)
        #expect(TaskResourceValidation.normalizeBody("  keep  spaces  ") == "keep  spaces")
        #expect(TaskResourceValidation.issue(title: String(repeating: "a", count: 121)) == .titleTooLong)
        #expect(TaskResourceValidation.issueForTextBody(title: "", body: String(repeating: "b", count: 100_001)) == .bodyTooLong)
        #expect(TaskResourceValidation.issueForTextBody(title: "", body: "ls -la") == nil)
        #expect(WidgetReloadClassifier.kinds(for: .resourcesUpdated).isEmpty)
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .resourcesUpdated) == false)
    }

    // MARK: - Paths

    @Test("Managed paths reject traversal and absolute injection")
    func pathSafety() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let relative = TaskResourceFilePath.relativePath(taskID: UUID(), resourceID: UUID(), fileExtension: "png")
        #expect(relative.contains("..") == false)
        let resolved = try TaskResourceFilePath.resolveFileURL(root: root, relative: relative)
        #expect(resolved.path.hasPrefix(root.path))

        #expect(throws: TaskResourceStorageError.pathTraversal) {
            try TaskResourceFilePath.resolveFileURL(root: root, relative: "../escape")
        }
        #expect(throws: TaskResourceStorageError.pathTraversal) {
            try TaskResourceFilePath.resolveFileURL(root: root, relative: "/etc/passwd")
        }
        #expect(TaskResourceFilePath.sanitizeExtension("../../txt") != "../../txt")
    }

    // MARK: - Model CRUD / hierarchy

    @Test("Create resources on root and subtask; cascade and promote preserve files")
    func modelAndHierarchy() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = try makeFileStore()
        let resources = TaskResourceRepository(context: context, fileStore: store)
        let tasks = TaskRepository(context: context)
        let (project, root) = try seedTask(context)

        let link = try resources.createLink(
            taskID: root.id,
            title: "Docs",
            url: URL(string: "https://example.com/api")!
        )
        #expect(link.task?.id == root.id)
        #expect((root.resources ?? []).count == 1)

        let child = try tasks.createSubtask(parentTaskID: root.id, title: "Child")
        let code = try resources.createTextResource(
            taskID: child.id,
            kind: .codeSnippet,
            title: "Swift",
            body: "let x = 1\nlet y = 2",
            languageIdentifier: "Swift"
        )
        #expect(code.body?.contains("\n") == true)

        let fileResourceID = UUID()
        let tmp = try writeTempFile(data: Data("hello world".utf8), name: "note-\(UUID()).txt")
        let imported = try store.importFile(from: tmp, taskID: child.id, resourceID: fileResourceID)
        let fileRes = try resources.createImportedFile(
            taskID: child.id,
            resourceID: fileResourceID,
            importedFile: imported
        )
        #expect(fileRes.fileSize == Int64("hello world".utf8.count))
        #expect(store.fileExists(at: imported.relativePath))

        // Deleting resource keeps task
        _ = try resources.deleteResource(resourceID: link.id)
        #expect(try tasks.fetchTask(id: root.id) != nil)

        // Delete child removes its resources; parent remains
        let childPaths = resources.managedPaths(for: child)
        try tasks.delete(child, mode: .deleteDescendants)
        #expect(try resources.fetchResource(id: code.id) == nil)
        for path in childPaths {
            #expect(store.fileExists(at: path) == false)
        }

        let keep = try tasks.createSubtask(parentTaskID: root.id, title: "Keep")
        _ = try resources.createTextResource(
            taskID: keep.id,
            kind: .text,
            title: "Note",
            body: "keep me"
        )
        try tasks.delete(root, mode: .promoteChildren)
        #expect(keep.isRoot)
        #expect((keep.resources ?? []).isEmpty == false)
        #expect(try resources.fetchResources(taskID: keep.id).count == 1)

        // Project archive preserves resources; delete cleans
        let p2 = try ProjectRepository(context: context).create(name: "Del")
        let t2 = try tasks.create(in: p2, title: "T2")
        let pathBody = try writeTempFile(data: Data("pdf".utf8), name: "a.pdf")
        let imp = try store.importFile(from: pathBody, taskID: t2.id, resourceID: UUID())
        _ = try resources.createImportedFile(taskID: t2.id, resourceID: UUID(), importedFile: imp)
        try ProjectRepository(context: context).archive(p2)
        #expect((t2.resources ?? []).isEmpty == false)
        try ProjectRepository(context: context).delete(p2)
        #expect(try tasks.fetchTask(id: t2.id) == nil)
        _ = project
    }

    // MARK: - File store

    @Test("Import stores copy; empty/oversized rejected; failed persistence cleans staged file")
    func fileStorage() throws {
        let store = try makeFileStore()
        let taskID = UUID()
        let resourceID = UUID()

        let empty = try writeTempFile(data: Data(), name: "empty-\(UUID()).bin")
        #expect(throws: TaskResourceStorageError.emptyFile) {
            try store.importFile(from: empty, taskID: taskID, resourceID: resourceID)
        }

        let huge = try writeTempFile(data: Data(count: Int(TaskResourceFilePath.maxFileBytes) + 1), name: "huge-\(UUID()).bin")
        #expect(throws: TaskResourceStorageError.fileTooLarge) {
            try store.importFile(from: huge, taskID: taskID, resourceID: UUID())
        }

        let okURL = try writeTempFile(data: Data("payload".utf8), name: "ok-\(UUID()).txt")
        let imported = try store.importFile(from: okURL, taskID: taskID, resourceID: resourceID)
        #expect(imported.originalFileName.contains("ok"))
        #expect(imported.fileSize == 7)
        #expect(store.fileExists(at: imported.relativePath))
        let resolved = try store.fileURL(for: imported.relativePath)
        #expect(try Data(contentsOf: resolved) == Data("payload".utf8))

        // Traversal delete protection via resolve
        #expect(throws: TaskResourceStorageError.pathTraversal) {
            try store.fileURL(for: "../secret")
        }

        try store.deleteFile(at: imported.relativePath)
        #expect(store.fileExists(at: imported.relativePath) == false)

        // Persistence failure cleans staged: simulate createImportedFile missing task
        let container = try makeContainer()
        let context = ModelContext(container)
        let resources = TaskResourceRepository(context: context, fileStore: store)
        let stagedTaskID = UUID()
        let stagedID = UUID()
        let stagedURL = try writeTempFile(data: Data("tmp".utf8), name: "stg-\(UUID()).txt")
        let staged = try store.importFile(from: stagedURL, taskID: stagedTaskID, resourceID: stagedID)
        #expect(store.fileExists(at: staged.relativePath))
        do {
            _ = try resources.createImportedFile(
                taskID: UUID(),
                resourceID: stagedID,
                importedFile: staged
            )
            Issue.record("Expected missing task")
        } catch RepositoryValidationError.missingTask {
            #expect(store.fileExists(at: staged.relativePath) == false)
        }
    }

    // MARK: - Ordering & drafts

    @Test("Resource ordering and draft replace")
    func orderingAndDrafts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = try makeFileStore()
        let resources = TaskResourceRepository(context: context, fileStore: store)
        let (_, task) = try seedTask(context)

        let a = try resources.createTextResource(taskID: task.id, kind: .text, title: "A", body: "a")
        let b = try resources.createTextResource(taskID: task.id, kind: .text, title: "B", body: "b")
        let c = try resources.createTextResource(taskID: task.id, kind: .text, title: "C", body: "c")
        #expect(try resources.fetchResources(taskID: task.id).map(\.id) == [a.id, b.id, c.id])

        #expect(try resources.moveResource(resourceID: c.id, before: a.id))
        #expect(try resources.fetchResources(taskID: task.id).map(\.id) == [c.id, a.id, b.id])
        #expect(try resources.moveResource(resourceID: c.id, before: nil))
        #expect(try resources.fetchResources(taskID: task.id).map(\.id) == [a.id, b.id, c.id])
        #expect(try resources.moveResource(resourceID: a.id, before: a.id) == false)

        var drafts = TaskResourceDraftBuilder.drafts(from: try resources.fetchResources(taskID: task.id))
        #expect(drafts.count == 3)
        drafts.removeAll { $0.persistedResourceID == b.id }
        drafts.append(TaskResourceDraft(kind: .terminalCommand, title: "Cmd", body: "echo hi"))
        try resources.replaceDraftResources(taskID: task.id, drafts: drafts)
        let after = try resources.fetchResources(taskID: task.id)
        #expect(after.count == 3)
        #expect(after.contains(where: { $0.id == a.id }))
        #expect(after.contains(where: { $0.id == b.id }) == false)
        #expect(after.contains(where: { $0.kind == .terminalCommand }))

        // Parent updatedAt bumped
        #expect(task.updatedAt > task.createdAt)
    }

    // MARK: - Integration

    @Test("Resources ignore search/widgets; reminder/labels/checklists intact")
    func integration() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = try makeFileStore()
        let resources = TaskResourceRepository(context: context, fileStore: store)
        let tasks = TaskRepository(context: context)
        let labels = LabelRepository(context: context)
        let checklists = ChecklistRepository(context: context)
        let (project, task) = try seedTask(context)
        let label = try labels.create(name: "Core")
        let reminder = Date().addingTimeInterval(9000)
        try tasks.update(
            task,
            title: "Ship API",
            taskDescription: "",
            status: .todo,
            priority: .high,
            dueDate: nil,
            reminderDate: reminder,
            notes: "",
            labelIDs: [label.id]
        )
        _ = try checklists.createItem(taskID: task.id, title: "Check A")
        _ = try resources.createLink(taskID: task.id, title: "", url: URL(string: "https://example.com/secret-path")!)
        _ = try resources.createTextResource(
            taskID: task.id,
            kind: .codeSnippet,
            title: "",
            body: "uniqueCodeTokenXYZ"
        )

        #expect(task.reminderDate == reminder)
        #expect((task.labels ?? []).count == 1)
        #expect((task.checklist ?? []).count == 1)

        let searchable = SearchMapping.task(task)!
        let byCode = SearchBuilder.build(
            query: "uniqueCodeTokenXYZ",
            projects: [],
            tasks: [searchable],
            includeArchived: false
        )
        #expect(byCode.taskTotalCount == 0)

        let dash = DashboardMapping.taskInput(from: task)!
        let snap = WidgetSnapshotBuilder.highPrioritySnapshot(tasks: [dash])
        #expect(snap.tasks.first?.title == "Ship API")
        _ = project
    }
}
