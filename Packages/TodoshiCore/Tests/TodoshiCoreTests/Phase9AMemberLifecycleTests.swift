import Foundation
import Testing
@testable import TodoshiCore

struct Phase9AMemberLifecycleTests {
    private func snapshot(
        id: String,
        assignee: String? = nil,
        editors: [String] = [],
        parent: String? = nil,
        deletedAt: Date? = nil
    ) -> MemberRemovalTaskSnapshot {
        MemberRemovalTaskSnapshot(
            id: id,
            assigneeUID: assignee,
            editorUIDs: editors,
            parentTaskId: parent,
            deletedAt: deletedAt
        )
    }

    @Test("Owner removal policy rejects self and owner targets")
    func ownerRemovalPolicy() {
        #expect(
            MemberRemovalCleanupPolicy.ownerCanRemoveMember(
                ownerUID: "owner",
                targetUID: "member",
                targetRole: .member
            )
        )
        #expect(
            !MemberRemovalCleanupPolicy.ownerCanRemoveMember(
                ownerUID: "owner",
                targetUID: "owner",
                targetRole: .owner
            )
        )
        #expect(
            !MemberRemovalCleanupPolicy.ownerCanRemoveMember(
                ownerUID: "owner",
                targetUID: "owner",
                targetRole: .member
            )
        )
    }

    @Test("Self-leave policy requires matching UID and non-owner role")
    func selfLeavePolicy() {
        #expect(
            MemberRemovalCleanupPolicy.memberCanLeave(
                actingUID: "member",
                memberUID: "member",
                memberRole: .member
            )
        )
        #expect(
            !MemberRemovalCleanupPolicy.memberCanLeave(
                actingUID: "member",
                memberUID: "other",
                memberRole: .member
            )
        )
        #expect(
            !MemberRemovalCleanupPolicy.memberCanLeave(
                actingUID: "owner",
                memberUID: "owner",
                memberRole: .owner
            )
        )
    }

    @Test("Cleanup planning clears assignee and removes editor UID")
    func cleanupPlanning() {
        let tasks = [
            snapshot(id: "t1", assignee: "bob", editors: ["bob", "carol"]),
            snapshot(id: "t2", editors: ["bob"]),
            snapshot(id: "t3", assignee: "carol"),
        ]
        let plan = MemberRemovalCleanupPolicy.planCleanup(targetUID: "bob", tasks: tasks)
        #expect(plan.updates.count == 2)
        #expect(plan.updates.contains(MemberRemovalTaskCleanupUpdate(taskID: "t1", clearAssignee: true, removeEditorUID: true)))
        #expect(plan.updates.contains(MemberRemovalTaskCleanupUpdate(taskID: "t2", clearAssignee: false, removeEditorUID: true)))
    }

    @Test("Deduplicates tasks matching assignee and editor queries")
    func deduplication() {
        let assigneeHit = snapshot(id: "t1", assignee: "bob", editors: ["bob"])
        let editorHit = snapshot(id: "t1", assignee: "bob", editors: ["bob"])
        let merged = MemberRemovalCleanupPolicy.deduplicatedLiveRootTasks(
            assigneeMatches: [assigneeHit],
            editorMatches: [editorHit]
        )
        #expect(merged.count == 1)
        #expect(merged[0].id == "t1")
    }

    @Test("Skips deleted and subtask snapshots")
    func liveRootOnly() {
        let tasks = [
            snapshot(id: "root", assignee: "bob"),
            snapshot(id: "child", assignee: "bob", parent: "root"),
            snapshot(id: "deleted", assignee: "bob", deletedAt: .now),
        ]
        let plan = MemberRemovalCleanupPolicy.planCleanup(targetUID: "bob", tasks: tasks)
        #expect(plan.updates.count == 1)
        #expect(plan.updates[0].taskID == "root")
    }

    @Test("Idempotent cleanup fields return nil when already clean")
    func idempotentCleanup() {
        let clean = snapshot(id: "t1", assignee: nil, editors: ["carol"])
        #expect(MemberRemovalCleanupPolicy.cleanupFields(targetUID: "bob", task: clean) == nil)
        let dirty = snapshot(id: "t2", assignee: "bob", editors: ["bob"])
        let fields = MemberRemovalCleanupPolicy.cleanupFields(targetUID: "bob", task: dirty)
        #expect(fields?.clearAssignee == true)
        #expect(fields?.editorUIDs.isEmpty == true)
    }

    @Test("Chunk planning respects batch ceiling")
    func chunkPlanning() {
        let items = Array(0..<850).map { $0 }
        let chunks = MemberRemovalCleanupPolicy.chunkUpdates(items, chunkSize: 400)
        #expect(chunks.count == 3)
        #expect(chunks[0].count == 400)
        #expect(chunks[1].count == 400)
        #expect(chunks[2].count == 50)
    }

    @Test("Eviction policy never converts shared projects to personal")
    func evictionPolicy() {
        #expect(SharedProjectMemberEvictionPolicy.removesLocalSharedCache)
        #expect(!SharedProjectMemberEvictionPolicy.convertsToPersonal)
        #expect(SharedProjectMemberEvictionPolicy.preservesHistoricalSnapshotsInCloud)
    }

    @Test("Historical attribution is independent of membership cleanup")
    func historicalAttributionPreserved() {
        let task = snapshot(id: "done-item", assignee: "carol")
        let plan = MemberRemovalCleanupPolicy.planCleanup(targetUID: "bob", tasks: [task])
        #expect(plan.updates.isEmpty)
        #expect(
            UserFacingError.message(for: CollaborationError.memberRemoveFailed).isEmpty == false
        )
        #expect(
            UserFacingError.message(for: CollaborationError.memberLeaveFailed).isEmpty == false
        )
    }

    @Test("Tasks and checklist projects share the same cleanup policy")
    func projectTypeEquivalence() {
        let bobTask = snapshot(id: "tasks-root", assignee: "bob")
        let bobChecklist = snapshot(id: "checklist-root", assignee: "bob")
        let tasksPlan = MemberRemovalCleanupPolicy.planCleanup(targetUID: "bob", tasks: [bobTask])
        let checklistPlan = MemberRemovalCleanupPolicy.planCleanup(targetUID: "bob", tasks: [bobChecklist])
        #expect(tasksPlan.updates.count == checklistPlan.updates.count)
        #expect(tasksPlan.updates.allSatisfy { $0.clearAssignee })
        #expect(checklistPlan.updates.allSatisfy { $0.clearAssignee })
    }
}
