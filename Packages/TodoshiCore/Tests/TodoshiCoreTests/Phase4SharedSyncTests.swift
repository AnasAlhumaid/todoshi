import Foundation
import SwiftData
import Testing
@testable import TodoshiCore

struct Phase4SharedSyncTests {
    @Test("Conflict policy: newer remote wins; soft delete wins")
    func conflictPolicy() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        #expect(SharedProjectConflictPolicy.winner(localRemoteUpdatedAt: older, incomingRemoteUpdatedAt: newer) == .remote)
        #expect(SharedProjectConflictPolicy.winner(localRemoteUpdatedAt: newer, incomingRemoteUpdatedAt: older) == .local)
        #expect(SharedProjectConflictPolicy.winner(localRemoteUpdatedAt: newer, incomingRemoteUpdatedAt: newer) == .equal)
        #expect(SharedProjectConflictPolicy.winner(localRemoteUpdatedAt: nil, incomingRemoteUpdatedAt: nil) == .remote)
        #expect(SharedProjectConflictPolicy.winner(localRemoteUpdatedAt: newer, incomingRemoteUpdatedAt: nil) == .local)
        #expect(SharedProjectConflictPolicy.shouldApplyRemoteSoftDelete(remoteDeletedAt: newer, localExists: true))
        #expect(!SharedProjectConflictPolicy.shouldApplyRemoteSoftDelete(remoteDeletedAt: nil, localExists: true))
    }

    @Test("DTO apply does not stamp remoteUpdatedAt from non-authoritative placeholder")
    @MainActor
    func authoritativeRemoteUpdatedAt() throws {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let project = Project(name: "P", sharingMode: .shared)
        context.insert(project)
        let task = TaskItem(title: "T", project: project)
        task.remoteUpdatedAt = Date(timeIntervalSince1970: 50)
        context.insert(task)

        let placeholder = FirestoreTaskDTO(
            id: task.id,
            projectId: project.id,
            title: "T2",
            statusRaw: TaskStatus.inProgress.rawValue,
            priorityRaw: TaskPriority.none.rawValue,
            position: 1,
            createdAt: .now,
            updatedAt: Date(timeIntervalSince1970: 9_999_999),
            hasAuthoritativeRemoteUpdatedAt: false
        )
        FirestoreTaskMapping.apply(placeholder, to: task)
        #expect(task.title == "T2")
        #expect(task.status == .inProgress)
        #expect(task.remoteUpdatedAt == Date(timeIntervalSince1970: 50))

        let authoritative = FirestoreTaskDTO(
            id: task.id,
            projectId: project.id,
            title: "T3",
            statusRaw: TaskStatus.review.rawValue,
            priorityRaw: TaskPriority.high.rawValue,
            position: 2,
            createdAt: .now,
            updatedAt: Date(timeIntervalSince1970: 200),
            hasAuthoritativeRemoteUpdatedAt: true
        )
        FirestoreTaskMapping.apply(authoritative, to: task)
        #expect(task.remoteUpdatedAt == Date(timeIntervalSince1970: 200))
        #expect(task.status == .review)
    }

    @Test("Deterministic recurrence successor identity is stable and unique per generation")
    func deterministicSuccessor() {
        let series = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let a = SharedRecurrenceSuccessorIdentity.successorID(seriesID: series, generation: 1)
        let b = SharedRecurrenceSuccessorIdentity.successorID(seriesID: series, generation: 1)
        let c = SharedRecurrenceSuccessorIdentity.successorID(seriesID: series, generation: 2)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Binary resources excluded from cloud; text kinds allowed")
    func resourceCloudPolicy() {
        #expect(SharedTaskResourceSyncPolicy.isCloudSyncable(.link))
        #expect(SharedTaskResourceSyncPolicy.isCloudSyncable(.text))
        #expect(SharedTaskResourceSyncPolicy.isCloudSyncable(.codeSnippet))
        #expect(SharedTaskResourceSyncPolicy.isCloudSyncable(.terminalCommand))
        #expect(!SharedTaskResourceSyncPolicy.isCloudSyncable(.image))
        #expect(!SharedTaskResourceSyncPolicy.isCloudSyncable(.pdf))
        #expect(SharedTaskResourceSyncPolicy.shouldExcludeFromCloudSeed(.file))
    }

    @Test("Account isolation hides shared projects for wrong or missing UID")
    func accountIsolation() {
        #expect(
            SharedProjectAccountIsolationPolicy.isVisible(
                sharingMode: .personal,
                collaborationOwnerUID: nil,
                currentUID: nil
            )
        )
        #expect(
            !SharedProjectAccountIsolationPolicy.isVisible(
                sharingMode: .shared,
                collaborationOwnerUID: "a",
                currentUID: nil
            )
        )
        #expect(
            !SharedProjectAccountIsolationPolicy.isVisible(
                sharingMode: .shared,
                collaborationOwnerUID: "a",
                currentUID: "b"
            )
        )
        #expect(
            SharedProjectAccountIsolationPolicy.isVisible(
                sharingMode: .shared,
                collaborationOwnerUID: "a",
                currentUID: "a"
            )
        )
        #expect(!SharedProjectAccountIsolationPolicy.canMutateShared(sharingMode: .shared, currentUID: nil))
        #expect(SharedProjectAccountIsolationPolicy.canMutateShared(sharingMode: .personal, currentUID: nil))
    }

    @Test("Seed policy requires explicit marker; empty tasks do not prove seeded")
    func seedPolicy() {
        #expect(SharedProjectSeedPolicy.needsOwnerSeed(isOwner: true, contentSeededAt: nil, contentSchemaVersion: nil))
        #expect(!SharedProjectSeedPolicy.needsOwnerSeed(isOwner: true, contentSeededAt: .now, contentSchemaVersion: 1))
        #expect(!SharedProjectSeedPolicy.needsOwnerSeed(isOwner: false, contentSeededAt: nil, contentSchemaVersion: nil))
        #expect(!SharedProjectSeedPolicy.isContentReady(contentSeededAt: nil))
        #expect(SharedProjectSeedPolicy.isContentReady(contentSeededAt: .now))
        #expect(SharedProjectContentSchema.currentVersion == 2)
        #expect(
            SharedProjectSeedPolicy.needsOwnerContentRepair(
                isOwner: true,
                contentSeededAt: .now,
                contentSchemaVersion: 1
            )
        )
        #expect(
            !SharedProjectSeedPolicy.needsOwnerContentRepair(
                isOwner: true,
                contentSeededAt: .now,
                contentSchemaVersion: 2
            )
        )
        #expect(
            !SharedProjectSeedPolicy.needsOwnerContentRepair(
                isOwner: true,
                contentSeededAt: nil,
                contentSchemaVersion: 1
            )
        )
    }

    @Test("FirestoreTaskDTO mapping round-trip fields including recurrence and labels")
    @MainActor
    func taskDTOMapping() throws {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let project = Project(name: "P")
        context.insert(project)
        let label = LabelTag(name: "L", colorHex: "#5B8DEF")
        context.insert(label)
        let task = TaskItem(
            title: "T",
            status: .todo,
            priority: .high,
            project: project,
            recurrenceRuleRaw: "daily",
            recurrenceInterval: 1,
            recurrenceSeriesID: UUID(),
            recurrenceGeneration: 0
        )
        task.labels = [label]
        context.insert(task)
        let dto = try #require(FirestoreTaskMapping.dto(from: task))
        #expect(dto.title == "T")
        #expect(dto.priorityRaw == TaskPriority.high.rawValue)
        #expect(dto.labelIds == [label.id])
        #expect(dto.recurrenceRuleRaw == "daily")

        let other = TaskItem(title: "X", project: project)
        context.insert(other)
        FirestoreTaskMapping.apply(dto, to: other)
        #expect(other.title == "T")
        #expect(other.priority == .high)
        #expect(other.remoteUpdatedAt == dto.updatedAt)
    }

    @Test("parentTaskID ↔ FirestoreTaskDTO.parentTaskId mapping is lossless")
    @MainActor
    func parentTaskIdMappingLossless() throws {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let project = Project(name: "Shared", sharingMode: .shared)
        context.insert(project)
        let parent = TaskItem(title: "Root", project: project)
        context.insert(parent)
        let child = TaskItem(title: "Child", project: project)
        child.parentTask = parent
        context.insert(child)

        let dto = try #require(FirestoreTaskMapping.dto(from: child))
        #expect(dto.parentTaskId == parent.id)
        #expect(dto.projectId == project.id)

        let reconstituted = TaskItem(title: "X", project: project)
        context.insert(reconstituted)
        FirestoreTaskMapping.apply(dto, to: reconstituted)
        reconstituted.parentTask = try TaskRepository(context: context).fetchTask(id: dto.parentTaskId!)
        #expect(reconstituted.parentTask?.id == parent.id)
        #expect(reconstituted.isRoot == false)

        let rootDTO = try #require(FirestoreTaskMapping.dto(from: parent))
        #expect(rootDTO.parentTaskId == nil)
    }

    @Test("Seed upload list includes roots and subtasks; roots first")
    @MainActor
    func seedIncludesSubtasks() throws {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let project = Project(name: "P", sharingMode: .shared)
        context.insert(project)
        let root = TaskItem(title: "Root", project: project)
        context.insert(root)
        let child = TaskItem(title: "Sub", project: project)
        child.parentTask = root
        context.insert(child)
        let deleted = TaskItem(title: "Gone", project: project)
        deleted.deletedAt = .now
        context.insert(deleted)
        try context.save()

        let upload = SharedProjectSeedPolicy.tasksForCloudUpload(from: project.tasks ?? [])
        #expect(upload.map(\.id) == [root.id, child.id])
        #expect(upload.first?.parentTask == nil)
        #expect(upload.last?.parentTask?.id == root.id)
    }

    @Test("Hierarchy reconcile preserves parent UUID when parent missing; resolves later")
    func hierarchyReconcileOrdering() {
        let parentID = UUID()
        let childID = UUID()
        let early = SharedProjectHierarchyReconcilePolicy.parentLink(
            parentTaskId: parentID,
            knownLocalTaskIDs: [childID]
        )
        #expect(early.attachParentID == nil)
        #expect(early.pendingParentID == parentID)

        let pending = [childID: parentID]
        let afterParent = SharedProjectHierarchyReconcilePolicy.resolvePending(
            pendingByChild: pending,
            knownLocalTaskIDs: [childID, parentID]
        )
        #expect(afterParent.resolved[childID] == parentID)
        #expect(afterParent.stillPending.isEmpty)

        let rootLink = SharedProjectHierarchyReconcilePolicy.parentLink(
            parentTaskId: nil,
            knownLocalTaskIDs: [parentID]
        )
        #expect(rootLink.attachParentID == nil)
        #expect(rootLink.pendingParentID == nil)
    }

    @Test("createSubtask on shared project emits cloud upsert hook")
    @MainActor
    func createSubtaskEmitsMutation() throws {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let project = Project(name: "Shared", sharingMode: .shared)
        context.insert(project)
        let tasks = TaskRepository(context: context)
        let root = try tasks.create(in: project, title: "Root")

        final class EventBox: @unchecked Sendable {
            var events: [SharedProjectMutationHook.Event] = []
        }
        let box = EventBox()
        SharedProjectMutationHook.handler = { event in
            box.events.append(event)
        }
        defer { SharedProjectMutationHook.handler = nil }

        let child = try tasks.createSubtask(parentTaskID: root.id, title: "Subtask A")
        #expect(box.events.contains(.taskUpsert(projectID: project.id, taskID: child.id)))
        #expect(child.parentTask?.id == root.id)
        #expect(child.project?.id == project.id)
    }

    @Test("Shared soft-delete of subtask emits tombstone hook")
    @MainActor
    func softDeleteSubtaskEmits() throws {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let project = Project(name: "Shared", sharingMode: .shared)
        context.insert(project)
        let tasks = TaskRepository(context: context)
        let root = try tasks.create(in: project, title: "Root")
        let child = try tasks.createSubtask(parentTaskID: root.id, title: "Doomed")

        final class EventBox: @unchecked Sendable {
            var events: [SharedProjectMutationHook.Event] = []
        }
        let box = EventBox()
        SharedProjectMutationHook.handler = { event in
            box.events.append(event)
        }
        defer { SharedProjectMutationHook.handler = nil }

        try tasks.delete(child)
        #expect(box.events.contains(.taskSoftDelete(projectID: project.id, taskID: child.id)))
        #expect(child.deletedAt != nil)
    }

    @Test("Remote tombstone policy removes local subtask; idempotent parent mapping")
    @MainActor
    func remoteTombstoneAndIdempotentHierarchy() throws {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let project = Project(name: "Shared", sharingMode: .shared)
        context.insert(project)
        let parent = TaskItem(title: "Root", project: project)
        context.insert(parent)
        let child = TaskItem(title: "Sub", project: project)
        child.parentTask = parent
        context.insert(child)
        try context.save()

        #expect(SharedProjectConflictPolicy.shouldApplyRemoteSoftDelete(remoteDeletedAt: .now, localExists: true))
        context.delete(child)
        try context.save()
        #expect(try TaskRepository(context: context).fetchTask(id: child.id) == nil)
        #expect(try TaskRepository(context: context).fetchRootTasks(projectID: project.id, status: .todo).map(\.id) == [parent.id])

        let dto = try #require(FirestoreTaskMapping.dto(from: parent))
        FirestoreTaskMapping.apply(dto, to: parent)
        FirestoreTaskMapping.apply(dto, to: parent)
        #expect(parent.parentTask == nil)
        #expect(try TaskRepository(context: context).fetchRootTasks(projectID: project.id, status: .todo).count == 1)
    }

    @Test("Schema V8 is current; permission loss does not convert to personal")
    func schemaAndPermissionPolicy() {
        #expect(TodoshiSchema.currentVersion == TodoshiSchemaV9.versionIdentifier)
        #expect(!SharedProjectPermissionLossPolicy.convertToPersonalOnPermissionDenied)
        #expect(SharedProjectPermissionLossPolicy.stopListenersOnPermissionDenied)
    }

    @Test("Recurrence completion uses deterministic successor ID (idempotent)")
    @MainActor
    func recurrenceDeterministicCreate() throws {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let project = Project(name: "Shared Recurrence")
        context.insert(project)
        let tasks = TaskRepository(context: context)
        let due = Date(timeIntervalSince1970: 1_700_000_000)
        let task = try tasks.create(
            in: project,
            title: "Repeat",
            dueDate: due,
            recurrenceRule: TaskRecurrenceRule(kind: .daily)
        )
        let series = try #require(task.recurrenceSeriesID)
        try tasks.complete(task)
        let nextID = try #require(task.nextOccurrenceID)
        let expected = SharedRecurrenceSuccessorIdentity.successorID(seriesID: series, generation: 1)
        #expect(nextID == expected)
        // Second complete is idempotent — same nextOccurrenceID.
        try tasks.complete(task)
        #expect(task.nextOccurrenceID == expected)
    }
}
