import Foundation
import FirebaseAuth
import FirebaseFirestore
import TodoshiCore

/// Cloud-side account deletion via authenticated Firestore client + Security Rules.
/// Firebase Auth `currentUser.delete()` is performed by the auth layer AFTER this succeeds.
final class AccountDeletionService: AccountDeletionCloudPerforming, @unchecked Sendable {
    static let shared = AccountDeletionService()

    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    var isConfigured: Bool { FirebaseBootstrap.isConfigured }

    // MARK: - Discovery

    func discoverProjects(uid: String) async throws -> [AccountDeletionProjectSnapshot] {
        guard isConfigured else { throw CollaborationError.notConfigured }
        let snap = try await db.collection("projects")
            .whereField("memberIds", arrayContains: uid)
            .getDocuments()

        var results: [AccountDeletionProjectSnapshot] = []
        for doc in snap.documents {
            let data = doc.data()
            let ownerId = data["ownerId"] as? String ?? ""
            let memberIds = data["memberIds"] as? [String] ?? []
            let role: ProjectMemberRole = ownerId == uid ? .owner : .member
            results.append(
                AccountDeletionProjectSnapshot(
                    projectID: doc.documentID,
                    ownerId: ownerId,
                    memberIds: memberIds,
                    role: role
                )
            )
        }
        return results
    }

    func loadTodoshiId(uid: String) async throws -> String? {
        let snap = try await db.collection("users").document(uid).getDocument()
        return TodoshiIdentityProvisioningPolicy.normalized(snap.data()?["todoshiId"] as? String)
    }

    func buildPlan(uid: String) async throws -> AccountDeletionPlan {
        let projects = try await discoverProjects(uid: uid)
        async let comments = fetchOwnComments(uid: uid)
        async let completionTasks = fetchTasks(field: "completedByUID", uid: uid)
        async let activityTasks = fetchTasks(field: "lastActivityByUID", uid: uid)
        let (ownComments, completionHits, activityHits) = try await (comments, completionTasks, activityTasks)

        var attributionByKey: [String: AccountDeletionTaskAttributionRef] = [:]
        for task in completionHits + activityHits {
            let key = "\(task.projectID)/\(task.taskID)"
            if let existing = attributionByKey[key] {
                attributionByKey[key] = AccountDeletionTaskAttributionRef(
                    projectID: task.projectID,
                    taskID: task.taskID,
                    completedByUID: existing.completedByUID ?? task.completedByUID,
                    lastActivityByUID: existing.lastActivityByUID ?? task.lastActivityByUID
                )
            } else {
                attributionByKey[key] = task
            }
        }

        let todoshiId = try await loadTodoshiId(uid: uid)
        return AccountDeletionPlanningPolicy.buildPlan(
            uid: uid,
            projects: projects,
            comments: ownComments,
            attributionTasks: Array(attributionByKey.values),
            todoshiId: todoshiId
        )
    }

    // MARK: - Public deletion entry (after Profile confirmation; no provider reauth)

    func deleteAccount(
        plan: AccountDeletionPlan,
        onPhase: (@Sendable (AccountDeletionPhase) async -> Void)? = nil
    ) async throws {
        #if DEBUG
        let abbreviated = String(plan.uid.prefix(8))
        TodoshiDiagnostics.note("[AccountDeletionService] DELETE ACCOUNT CALLED")
        TodoshiDiagnostics.note("[AccountDeletionService] uid=\(abbreviated)")
        TodoshiDiagnostics.note("[AccountDeletionService] START cloud cleanup")
        #endif
        try await executeCloudCleanup(plan: plan, onPhase: onPhase)
    }

    // MARK: - Execute cloud cleanup (before Auth.delete)

    func executeCloudCleanup(
        plan: AccountDeletionPlan,
        onPhase: (@Sendable (AccountDeletionPhase) async -> Void)? = nil
    ) async throws {
        guard isConfigured else { throw CollaborationError.notConfigured }
        guard Auth.auth().currentUser?.uid == plan.uid else {
            throw CollaborationError.notAuthenticated
        }

        await onPhase?(.cleaningContent)
        try await withRemotePhaseTimeout {
            try await self.deleteOwnComments(plan.commentDeletes)
            try await self.scrubCompletionAttribution(plan.completionScrubs, uid: plan.uid)
            try await self.scrubActivityAttribution(plan.activityScrubs, uid: plan.uid)
        }
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletionService] authored comments complete")
        TodoshiDiagnostics.note("[AccountDeletionService] attribution scrub complete")
        #endif

        await onPhase?(.leavingProjects)
        try await withRemotePhaseTimeout {
            try await self.leaveMemberProjects(plan.memberProjectIDs, uid: plan.uid)
            try await self.revokeInvitesForAccountDeletion(
                uid: plan.uid,
                ownedProjectIDs: Set(plan.ownedProjectIDs)
            )
        }
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletionService] member projects complete")
        TodoshiDiagnostics.note("[AccountDeletionService] invites complete")
        #endif

        await onPhase?(.deletingOwnedProjects)
        try await withRemotePhaseTimeout {
            try await self.deleteOwnedProjects(plan.ownedProjectIDs)
        }
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletionService] owned projects complete")
        #endif

        await onPhase?(.deletingIdentity)
        try await withRemotePhaseTimeout {
            try await self.deleteIdentity(plan.identity)
        }
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletionService] identity docs complete")
        #endif
    }

    // MARK: - Collection-group queries

    private func fetchOwnComments(uid: String) async throws -> [AccountDeletionCommentRef] {
        let snap = try await db.collectionGroup("comments")
            .whereField("authorUID", isEqualTo: uid)
            .getDocuments()

        return snap.documents.compactMap { doc in
            let path = doc.reference.path.split(separator: "/").map(String.init)
            // projects/{pid}/tasks/{tid}/comments/{cid}
            guard path.count >= 6,
                  path[0] == "projects",
                  path[2] == "tasks",
                  path[4] == "comments"
            else { return nil }
            let author = doc.data()["authorUID"] as? String ?? ""
            guard author == uid else { return nil }
            return AccountDeletionCommentRef(
                projectID: path[1],
                taskID: path[3],
                commentID: path[5],
                authorUID: author
            )
        }
    }

    private func fetchTasks(field: String, uid: String) async throws -> [AccountDeletionTaskAttributionRef] {
        let snap = try await db.collectionGroup("tasks")
            .whereField(field, isEqualTo: uid)
            .getDocuments()

        return snap.documents.compactMap { doc in
            let path = doc.reference.path.split(separator: "/").map(String.init)
            // projects/{pid}/tasks/{tid}
            guard path.count >= 4,
                  path[0] == "projects",
                  path[2] == "tasks"
            else { return nil }
            let data = doc.data()
            return AccountDeletionTaskAttributionRef(
                projectID: path[1],
                taskID: path[3],
                completedByUID: data["completedByUID"] as? String,
                lastActivityByUID: data["lastActivityByUID"] as? String
            )
        }
    }

    // MARK: - Content cleanup

    private func deleteOwnComments(_ refs: [AccountDeletionCommentRef]) async throws {
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion] START authored comment deletion")
        #endif
        let chunks = AccountDeletionPlanningPolicy.chunkWrites(refs)
        for chunk in chunks {
            let batch = db.batch()
            for ref in chunk {
                let doc = db.collection("projects").document(ref.projectID)
                    .collection("tasks").document(ref.taskID)
                    .collection("comments").document(ref.commentID)
                batch.deleteDocument(doc)
            }
            try await batch.commit()
        }
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion] SUCCESS authored comment deletion")
        #endif
    }

    private func scrubCompletionAttribution(
        _ refs: [AccountDeletionTaskAttributionRef],
        uid: String
    ) async throws {
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion] START completion attribution scrub")
        #endif
        let chunks = AccountDeletionPlanningPolicy.chunkWrites(refs)
        for chunk in chunks {
            let batch = db.batch()
            var writes = 0
            for ref in chunk {
                guard ref.completedByUID == uid else { continue }
                let doc = db.collection("projects").document(ref.projectID)
                    .collection("tasks").document(ref.taskID)
                batch.updateData(
                    [
                        "completedByUID": NSNull(),
                        "completedByDisplayName": NSNull(),
                    ],
                    forDocument: doc
                )
                writes += 1
            }
            guard writes > 0 else { continue }
            try await batch.commit()
        }
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion] SUCCESS completion attribution scrub")
        #endif
    }

    private func scrubActivityAttribution(
        _ refs: [AccountDeletionTaskAttributionRef],
        uid: String
    ) async throws {
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion] START activity attribution scrub")
        #endif
        let chunks = AccountDeletionPlanningPolicy.chunkWrites(refs)
        for chunk in chunks {
            let batch = db.batch()
            var writes = 0
            for ref in chunk {
                guard ref.lastActivityByUID == uid else { continue }
                let doc = db.collection("projects").document(ref.projectID)
                    .collection("tasks").document(ref.taskID)
                batch.updateData(
                    ["lastActivityByUID": NSNull()],
                    forDocument: doc
                )
                writes += 1
            }
            guard writes > 0 else { continue }
            try await batch.commit()
        }
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion] SUCCESS activity attribution scrub")
        #endif
    }

    private func leaveMemberProjects(_ projectIDs: [String], uid: String) async throws {
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion] START leave member projects")
        #endif
        for projectID in projectIDs {
            guard let uuid = UUID(uuidString: projectID) else { continue }
            try await SharedProjectMemberLifecycleService.shared.leaveProject(
                projectID: uuid,
                actingUID: uid,
                memberRole: .member
            )
        }
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion] SUCCESS leave member projects")
        #endif
    }

    private func revokeInvitesForAccountDeletion(
        uid: String,
        ownedProjectIDs: Set<String>
    ) async throws {
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion] START invite revocation")
        #endif
        var byID: [String: QueryDocumentSnapshot] = [:]

        let createdSnap = try await db.collection(FirebaseInviteSecurityPolicy.collectionName)
            .whereField("createdBy", isEqualTo: uid)
            .getDocuments()
        for doc in createdSnap.documents {
            byID[doc.documentID] = doc
        }

        for projectID in ownedProjectIDs.sorted() {
            let projectSnap = try await db.collection(FirebaseInviteSecurityPolicy.collectionName)
                .whereField("projectId", isEqualTo: projectID)
                .getDocuments()
            for doc in projectSnap.documents {
                byID[doc.documentID] = doc
            }
        }

        let snapshots: [AccountDeletionInviteSnapshot] = byID.values.map { doc in
            let data = doc.data()
            let revokedAt = (data["revokedAt"] as? Timestamp)?.dateValue()
            return AccountDeletionInviteSnapshot(
                inviteID: doc.documentID,
                projectId: data["projectId"] as? String ?? "",
                createdBy: data["createdBy"] as? String ?? "",
                acceptedBy: data["acceptedBy"] as? String,
                revokedAt: revokedAt
            )
        }

        let toRevoke = AccountDeletionInviteCleanupPolicy.selectForRevocation(
            invites: snapshots,
            deletingUID: uid,
            ownedProjectIDs: ownedProjectIDs
        )
        guard !toRevoke.isEmpty else {
            #if DEBUG
            TodoshiDiagnostics.note("[AccountDeletion] SUCCESS invite revocation")
            #endif
            return
        }

        let docsByID = Dictionary(uniqueKeysWithValues: byID.map { ($0.key, $0.value) })
        let chunks = AccountDeletionPlanningPolicy.chunkWrites(toRevoke)
        for chunk in chunks {
            let batch = db.batch()
            var writes = 0
            for invite in chunk {
                guard let doc = docsByID[invite.inviteID] else { continue }
                batch.updateData(
                    ["revokedAt": FieldValue.serverTimestamp()],
                    forDocument: doc.reference
                )
                writes += 1
            }
            guard writes > 0 else { continue }
            try await batch.commit()
        }
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion] SUCCESS invite revocation")
        #endif
    }

    // MARK: - Owned project recursive delete

    private func deleteOwnedProjects(_ projectIDs: [String]) async throws {
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion] START owned project recursive deletion")
        #endif
        for projectID in projectIDs {
            try await deleteOwnedProjectTree(projectID: projectID)
        }
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion] SUCCESS owned project recursive deletion")
        #endif
    }

    /// Order: nested task subcollections → tasks → labels → members → project.
    private func deleteOwnedProjectTree(projectID: String) async throws {
        let projectRef = db.collection("projects").document(projectID)

        let taskRefs = try await listAllDocumentRefs(projectRef.collection("tasks"))
        for taskRef in taskRefs {
            try await deleteCollection(taskRef.collection("comments"))
            try await deleteCollection(taskRef.collection("checklist"))
            try await deleteCollection(taskRef.collection("resources"))
        }

        try await deleteCollection(projectRef.collection("tasks"))
        try await deleteCollection(projectRef.collection("labels"))
        try await deleteCollection(projectRef.collection("members"))
        try await projectRef.delete()
    }

    private func listAllDocumentRefs(_ collection: CollectionReference) async throws -> [DocumentReference] {
        var refs: [DocumentReference] = []
        var last: DocumentSnapshot?
        var page = 0
        let pageSize = AccountDeletionPlanningPolicy.maxWritesPerBatch
        while true {
            if page >= AccountDeletionPaginationPolicy.maxPagesPerCollection {
                throw CollaborationError.accountDeletionTimedOut
            }
            var query: Query = collection
                .order(by: FieldPath.documentID())
                .limit(to: pageSize)
            if let last {
                query = query.start(afterDocument: last)
            }
            let snap = try await query.getDocuments()
            let count = snap.documents.count
            #if DEBUG
            TodoshiDiagnostics.note("[AccountDeletion] list page=\(page) documents=\(count)")
            #endif
            guard count > 0 else { break }
            refs.append(contentsOf: snap.documents.map(\.reference))
            last = snap.documents.last
            let nextPage = AccountDeletionPaginationPolicy.nextPageIndex(after: page)
            if !AccountDeletionPaginationPolicy.shouldContinue(
                page: nextPage,
                documentCount: count,
                pageSize: pageSize
            ) {
                break
            }
            page = nextPage
        }
        return refs
    }

    private func deleteCollection(_ collection: CollectionReference) async throws {
        var page = 0
        let pageSize = AccountDeletionPlanningPolicy.maxWritesPerBatch
        while true {
            if page >= AccountDeletionPaginationPolicy.maxPagesPerCollection {
                throw CollaborationError.accountDeletionTimedOut
            }
            let snap = try await collection.limit(to: pageSize).getDocuments()
            let count = snap.documents.count
            #if DEBUG
            TodoshiDiagnostics.note("[AccountDeletion] delete page=\(page) documents=\(count)")
            #endif
            guard count > 0 else { return }
            let batch = db.batch()
            for doc in snap.documents {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
            page = AccountDeletionPaginationPolicy.nextPageIndex(after: page)
            if !AccountDeletionPaginationPolicy.shouldContinue(
                page: page,
                documentCount: count,
                pageSize: pageSize
            ) {
                return
            }
        }
    }

    // MARK: - Identity

    private func deleteIdentity(_ identity: AccountDeletionIdentityRefs) async throws {
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion] START users/publicIdentities/todoshiIds deletion")
        #endif
        if let todoshiId = identity.todoshiId,
           TodoshiIDPolicy.isValid(todoshiId) {
            try? await db.collection("todoshiIds").document(todoshiId).delete()
        }
        try? await db.collection("publicIdentities").document(identity.uid).delete()
        try await db.collection("users").document(identity.uid).delete()
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion] SUCCESS users/publicIdentities/todoshiIds deletion")
        #endif
    }

    private func withRemotePhaseTimeout<T: Sendable>(
        seconds: TimeInterval = AccountDeletionWatchdogPolicy.remotePhaseTimeoutSeconds,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CollaborationError.accountDeletionTimedOut
            }
            guard let result = try await group.next() else {
                throw CollaborationError.accountDeletionFailed
            }
            group.cancelAll()
            return result
        }
    }
}
