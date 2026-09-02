import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
struct PersistencePrototypeTests {
    private func makeInMemoryContext() throws -> ModelContext {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        return ModelContext(container)
    }

    @Test("In-memory container inserts and fetches by unique id")
    func uniqueIdentifierBehavior() throws {
        let context = try makeInMemoryContext()
        let id = UUID()
        let project = Project(id: id, name: "Alpha")
        context.insert(project)
        try context.save()

        let fetched = try context.fetch(
            FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        )
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Alpha")
    }

    @Test("Deleting project cascades to its tasks")
    func projectCascadingTaskDeletion() throws {
        let context = try makeInMemoryContext()
        let project = Project(name: "Cascade")
        context.insert(project)

        let t1 = TaskItem(title: "One", project: project)
        let t2 = TaskItem(title: "Two", project: project)
        context.insert(t1)
        context.insert(t2)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<TaskItem>()).count == 2)

        let projects = ProjectRepository(context: context)
        try projects.delete(project)

        #expect(try context.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).isEmpty)
    }

    @Test("Parent and child relationships")
    func parentChildRelationships() throws {
        let context = try makeInMemoryContext()
        let project = Project(name: "Tree")
        context.insert(project)

        let parent = TaskItem(title: "Parent", project: project)
        context.insert(parent)
        let child = TaskItem(title: "Child", project: project, parentTask: parent)
        context.insert(child)
        try context.save()

        #expect(child.parentTask?.id == parent.id)
        #expect((parent.subtasks ?? []).map(\.id).contains(child.id))
        #expect(child.isRoot == false)
        #expect(parent.isRoot == true)
    }

    @Test("Recursive descendant deletion deletes entire subtree")
    func recursiveDescendantDeletion() throws {
        let context = try makeInMemoryContext()
        let project = Project(name: "Delete Tree")
        context.insert(project)

        let root = TaskItem(title: "Root", project: project)
        context.insert(root)
        let mid = TaskItem(title: "Mid", project: project, parentTask: root)
        context.insert(mid)
        let leaf = TaskItem(title: "Leaf", project: project, parentTask: mid)
        context.insert(leaf)
        let unrelated = TaskItem(title: "Unrelated", project: project)
        context.insert(unrelated)
        try context.save()

        let repo = TaskRepository(context: context)
        #expect(repo.collectDescendants(of: root).count == 2)

        try repo.delete(root, mode: .deleteDescendants)

        let remaining = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.title == "Unrelated")
    }

    @Test("Promote children keeps direct children as root tasks")
    func promoteChildrenDeletion() throws {
        let context = try makeInMemoryContext()
        let project = Project(name: "Promote")
        context.insert(project)

        let parent = TaskItem(title: "Parent", project: project)
        context.insert(parent)
        let child = TaskItem(title: "Child", project: project, parentTask: parent)
        context.insert(child)
        try context.save()

        let repo = TaskRepository(context: context)
        try repo.delete(parent, mode: .promoteChildren)

        let remaining = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.title == "Child")
        #expect(remaining.first?.parentTask == nil)
        #expect(remaining.first?.project?.id == project.id)
    }

    @Test("Task and label many-to-many")
    func taskLabelManyToMany() throws {
        let context = try makeInMemoryContext()
        let project = Project(name: "Labels")
        context.insert(project)

        let label = LabelTag(name: "ios")
        context.insert(label)

        let taskA = TaskItem(title: "A", project: project)
        let taskB = TaskItem(title: "B", project: project)
        context.insert(taskA)
        context.insert(taskB)

        taskA.labels = [label]
        taskB.labels = [label]
        try context.save()

        #expect((taskA.labels ?? []).count == 1)
        #expect((label.tasks ?? []).count == 2)
    }

    @Test("App Group constants and store path (opens when container is available)")
    func appGroupStoreConfiguration() throws {
        #expect(AppGroupConstants.suiteName == "group.com.anashamad.Nexus")
        #expect(AppGroupConstants.storeFileName == "Nexus.store")

        // Container is only non-nil when the process is entitlements-enabled with the group.
        // Prefer an isolated probe file so tests never fight a stale production store schema.
        if let containerURL = AppGroupConstants.containerURL {
            let probeURL = containerURL.appendingPathComponent(
                "Nexus-test-probe-\(UUID().uuidString).store"
            )
            defer { try? FileManager.default.removeItem(at: probeURL) }

            let container = try ModelContainerFactory.makeContainer(kind: .file(probeURL))
            let context = ModelContext(container)
            let probe = Project(name: "AppGroupProbe")
            context.insert(probe)
            try context.save()
            #expect(FileManager.default.fileExists(atPath: probeURL.path))

            // Production path must also open (resets incompatible pre-release stores).
            _ = try ModelContainerFactory.makeContainer(kind: .appGroup)
        } else {
            #expect(AppGroupConstants.containerURL == nil)
        }
    }

    @Test("Two short-lived ModelContexts read the same on-disk store")
    func twoContextsSameStore() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-two-context-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let containerA = try ModelContainerFactory.makeContainer(kind: .file(url))
        let writeContext = ModelContext(containerA)
        let project = Project(name: "Shared Store")
        writeContext.insert(project)
        try writeContext.save()
        let projectID = project.id

        // New container opening the same URL (widget-like short-lived access).
        let containerB = try ModelContainerFactory.makeContainer(kind: .file(url))
        let readContext = ModelContext(containerB)
        let fetched = try readContext.fetch(
            FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectID })
        )
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Shared Store")
    }

    @Test("Widget-compatible read of tasks for a project")
    func widgetCompatibleRead() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-widget-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let writeContainer = try ModelContainerFactory.makeContainer(kind: .file(url))
        let write = ModelContext(writeContainer)
        try SeedData.populate(write)

        let readContainer = try ModelContainerFactory.makeContainer(kind: .file(url))
        let read = ModelContext(readContainer)
        let tasks = try read.fetch(FetchDescriptor<TaskItem>())
        #expect(tasks.isEmpty == false)
        #expect(tasks.contains { $0.title == "Design data layer" })
    }

    @Test("completedAt is set on done and cleared when leaving done")
    func completionMetadata() throws {
        let context = try makeInMemoryContext()
        let task = TaskItem(title: "Ship", status: .todo)
        context.insert(task)
        #expect(task.completedAt == nil)

        task.applyStatus(.done)
        #expect(task.completedAt != nil)
        let first = task.completedAt

        task.applyStatus(.done)
        #expect(task.completedAt == first)

        task.applyStatus(.todo)
        #expect(task.completedAt == nil)
    }

    @Test("Fractional position insert and normalization")
    func fractionalPositioning() {
        let a = FractionalPosition.initial()
        let b = FractionalPosition.after(a)
        let mid = FractionalPosition.between(lower: a, upper: b)
        #expect(mid > a && mid < b)

        #expect(FractionalPosition.needsNormalization(positions: [1, 1 + 1e-9]) == true)
        #expect(FractionalPosition.needsNormalization(positions: [1024, 2048]) == false)

        let normalized = FractionalPosition.normalizedPositions(count: 3)
        #expect(normalized == [1024, 2048, 3072])
    }

    @Test("Productivity metrics use completedAt not updatedAt")
    func productivityUsesCompletedAt() {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let interval = DateInterval(start: start, end: .now.addingTimeInterval(1))

        let completedInWindow: Date? = .now
        let incomplete: Date? = nil
        let count = ProductivityMetrics.completedCount(
            completedAtValues: [completedInWindow, incomplete],
            in: interval
        )
        #expect(count == 1)
        #expect(ProductivityMetrics.openCount(statuses: [.todo, .done, .review]) == 2)
    }

    @Test("Deep link quick-add parses")
    func deepLinkQuickAdd() {
        let url = URL(string: "nexus://quick-add")!
        #expect(NexusDeepLink(url: url) == .quickAdd)
        #expect(NexusDeepLink.quickAdd.url.absoluteString == "nexus://quick-add")
    }

    @Test("Seed data creates a consistent graph")
    func seedData() throws {
        let context = try makeInMemoryContext()
        let result = try SeedData.populate(context)
        #expect(try context.fetch(FetchDescriptor<Project>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).count >= 2)
        #expect(try context.fetch(FetchDescriptor<LabelTag>()).count == 2)

        let root = try TaskRepository(context: context).fetchTask(id: result.rootTaskID)
        #expect(root != nil)
        #expect((root?.checklist ?? []).isEmpty == false)
    }
}
