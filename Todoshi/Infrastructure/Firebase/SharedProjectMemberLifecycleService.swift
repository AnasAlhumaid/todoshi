import Foundation
import FirebaseFirestore
import TodoshiCore

/// Phase 9A — owner removal and member self-leave with task cleanup before revoke.
final class SharedProjectMemberLifecycleService: @unchecked Sendable {
    static let shared = SharedProjectMemberLifecycleService()

    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    var isConfigured: Bool { FirebaseBootstrap.isConfigured }

    func removeMember(
        projectID: UUID,
        targetUID: String,
        actingUID: String,
        targetRole: ProjectMemberRole
    ) async throws {
        guard isConfigured else { throw CollaborationError.notConfigured }
        guard MemberRemovalCleanupPolicy.ownerCanRemoveMember(
            ownerUID: actingUID,
            targetUID: targetUID,
            targetRole: targetRole
        ) else {
            throw CollaborationError.taskEditPermissionDenied
        }
        try await performDeparture(
            projectID: projectID,
            targetUID: targetUID,
            failure: .memberRemoveFailed
        )
    }

    func leaveProject(
        projectID: UUID,
        actingUID: String,
        memberRole: ProjectMemberRole
    ) async throws {
        guard isConfigured else { throw CollaborationError.notConfigured }
        guard MemberRemovalCleanupPolicy.memberCanLeave(
            actingUID: actingUID,
            memberUID: actingUID,
            memberRole: memberRole
        ) else {
            throw CollaborationError.taskEditPermissionDenied
        }
        try await performDeparture(
            projectID: projectID,
            targetUID: actingUID,
            failure: .memberLeaveFailed
        )
    }

    private func performDeparture(
        projectID: UUID,
        targetUID: String,
        failure: CollaborationError
    ) async throws {
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        let projectRef = db.collection("projects").document(remoteID)
        let tasksRef = projectRef.collection("tasks")

        let assigneeSnap: QuerySnapshot
        let editorSnap: QuerySnapshot
        do {
            async let assigneeQuery = tasksRef
                .whereField("assigneeUID", isEqualTo: targetUID)
                .getDocuments()
            async let editorQuery = tasksRef
                .whereField("editorUIDs", arrayContains: targetUID)
                .getDocuments()
            assigneeSnap = try await assigneeQuery
            editorSnap = try await editorQuery
        } catch {
            throw failure
        }

        let assigneeSnapshots = Self.mapSnapshots(assigneeSnap.documents)
        let editorSnapshots = Self.mapSnapshots(editorSnap.documents)
        let liveRoots = MemberRemovalCleanupPolicy.deduplicatedLiveRootTasks(
            assigneeMatches: assigneeSnapshots,
            editorMatches: editorSnapshots
        )
        let plan = MemberRemovalCleanupPolicy.planCleanup(targetUID: targetUID, tasks: liveRoots)

        do {
            try await applyCleanup(
                plan: plan,
                targetUID: targetUID,
                tasksRef: tasksRef,
                liveTasksByID: Dictionary(uniqueKeysWithValues: liveRoots.map { ($0.id, $0) })
            )
            try await revokeMembership(
                projectRef: projectRef,
                targetUID: targetUID
            )
        } catch {
            throw failure
        }
    }

    private func applyCleanup(
        plan: MemberRemovalTaskCleanupPlan,
        targetUID: String,
        tasksRef: CollectionReference,
        liveTasksByID: [String: MemberRemovalTaskSnapshot]
    ) async throws {
        let chunks = MemberRemovalCleanupPolicy.chunkUpdates(plan.updates)
        for chunk in chunks {
            let batch = db.batch()
            var writes = 0
            for update in chunk {
                guard let task = liveTasksByID[update.taskID],
                      let fields = MemberRemovalCleanupPolicy.cleanupFields(
                          targetUID: targetUID,
                          task: task
                      )
                else { continue }

                var payload: [String: Any] = [
                    "updatedAt": FieldValue.serverTimestamp(),
                ]
                if fields.clearAssignee {
                    payload["assigneeUID"] = NSNull()
                }
                if update.removeEditorUID {
                    payload["editorUIDs"] = fields.editorUIDs
                }
                batch.updateData(payload, forDocument: tasksRef.document(update.taskID))
                writes += 1
            }
            guard writes > 0 else { continue }
            try await batch.commit()
        }
    }

    private func revokeMembership(
        projectRef: DocumentReference,
        targetUID: String
    ) async throws {
        let batch = db.batch()
        batch.deleteDocument(projectRef.collection("members").document(targetUID))
        batch.updateData(
            ["memberIds": FieldValue.arrayRemove([targetUID])],
            forDocument: projectRef
        )
        try await batch.commit()
    }

    private static func mapSnapshots(_ documents: [QueryDocumentSnapshot]) -> [MemberRemovalTaskSnapshot] {
        documents.map { doc in
            let data = doc.data()
            let assignee = data["assigneeUID"] as? String
            let editors = data["editorUIDs"] as? [String] ?? []
            let parent = data["parentTaskId"] as? String
            let deletedAt = (data["deletedAt"] as? Timestamp)?.dateValue()
            return MemberRemovalTaskSnapshot(
                id: doc.documentID,
                assigneeUID: assignee,
                editorUIDs: editors,
                parentTaskId: parent,
                deletedAt: deletedAt
            )
        }
    }
}
