import Foundation
import FirebaseFirestore
import TodoshiCore

/// Firestore-only realtime comments for a single shared task. No SwiftData / no app-wide listeners.
final class TaskCommentService: @unchecked Sendable {
    static let shared = TaskCommentService()

    private let db: Firestore
    private let lock = NSLock()
    private var listeners: [UUID: ListenerRegistration] = [:]

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    var isConfigured: Bool {
        FirebaseBootstrap.isConfigured
    }

    private func commentsCollection(projectID: UUID, taskID: UUID) -> CollectionReference {
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        return db.collection("projects")
            .document(remoteID)
            .collection("tasks")
            .document(taskID.uuidString)
            .collection("comments")
    }

    /// Realtime comments while Task Detail comments section is active. Ordered by createdAt ascending.
    @discardableResult
    func startListening(
        projectID: UUID,
        taskID: UUID,
        onChange: @escaping @Sendable ([TaskComment]) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) -> UUID {
        let token = UUID()
        let registration = commentsCollection(projectID: projectID, taskID: taskID)
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onError(error)
                    return
                }
                guard let snapshot else {
                    onError(CollaborationError.notConfigured)
                    return
                }
                let comments = snapshot.documents.compactMap(Self.mapComment)
                onChange(TaskCommentOrderingPolicy.orderedVisible(from: comments))
            }
        lock.lock()
        listeners[token] = registration
        lock.unlock()
        return token
    }

    func stopListening(_ token: UUID?) {
        guard let token else { return }
        lock.lock()
        let registration = listeners.removeValue(forKey: token)
        lock.unlock()
        registration?.remove()
    }

    func createComment(
        projectID: UUID,
        taskID: UUID,
        commentID: UUID = UUID(),
        authorUID: String,
        authorDisplayName: String,
        body: String,
        at date: Date = .now
    ) async throws {
        guard isConfigured else { throw CollaborationError.notConfigured }
        guard case .valid(let trimmed) = TaskCommentBodyPolicy.validate(body) else {
            throw CollaborationError.commentInvalidBody
        }
        let display = SharedProjectRolePermissions.displayNameSnapshot(
            preferred: authorDisplayName,
            email: nil,
            uid: authorUID
        )
        let rootTaskID = try await resolveRootTaskID(projectID: projectID, taskID: taskID)
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        let commentRef = commentsCollection(projectID: projectID, taskID: taskID).document(commentID.uuidString)
        let rootRef = db.collection("projects").document(remoteID)
            .collection("tasks").document(rootTaskID.uuidString)
        let data: [String: Any] = [
            "id": commentID.uuidString,
            "authorUID": authorUID,
            "authorDisplayName": display,
            "body": trimmed,
            "createdAt": Timestamp(date: date),
            "updatedAt": Timestamp(date: date),
            "deletedAt": NSNull(),
        ]
        let batch = db.batch()
        batch.setData(data, forDocument: commentRef)
        batch.updateData([
            "lastActivityAt": FieldValue.serverTimestamp(),
            "lastActivityByUID": authorUID,
            "lastActivityKind": TaskCollaborationActivityKind.commentAdded.rawValue,
            "updatedAt": FieldValue.serverTimestamp(),
        ], forDocument: rootRef)
        try await batch.commit()
    }

    func updateBody(
        projectID: UUID,
        taskID: UUID,
        comment: TaskComment,
        body: String,
        at date: Date = .now
    ) async throws {
        guard isConfigured else { throw CollaborationError.notConfigured }
        guard case .valid(let trimmed) = TaskCommentBodyPolicy.validate(body) else {
            throw CollaborationError.commentInvalidBody
        }
        let rootTaskID = try await resolveRootTaskID(projectID: projectID, taskID: taskID)
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        let commentRef = commentsCollection(projectID: projectID, taskID: taskID).document(comment.id.uuidString)
        let rootRef = db.collection("projects").document(remoteID)
            .collection("tasks").document(rootTaskID.uuidString)
        let payload: [String: Any] = [
            "id": comment.id.uuidString,
            "authorUID": comment.authorUID,
            "authorDisplayName": comment.authorDisplayName,
            "body": trimmed,
            "createdAt": Timestamp(date: comment.createdAt),
            "updatedAt": Timestamp(date: date),
            "deletedAt": NSNull(),
        ]
        let batch = db.batch()
        batch.setData(payload, forDocument: commentRef, merge: false)
        batch.updateData([
            "lastActivityAt": FieldValue.serverTimestamp(),
            "lastActivityByUID": comment.authorUID,
            "lastActivityKind": TaskCollaborationActivityKind.commentEdited.rawValue,
            "updatedAt": FieldValue.serverTimestamp(),
        ], forDocument: rootRef)
        try await batch.commit()
    }

    func softDelete(
        projectID: UUID,
        taskID: UUID,
        comment: TaskComment,
        at date: Date = .now
    ) async throws {
        guard isConfigured else { throw CollaborationError.notConfigured }
        try await commentsCollection(projectID: projectID, taskID: taskID)
            .document(comment.id.uuidString)
            .setData(
                [
                    "id": comment.id.uuidString,
                    "authorUID": comment.authorUID,
                    "authorDisplayName": comment.authorDisplayName,
                    "body": comment.body,
                    "createdAt": Timestamp(date: comment.createdAt),
                    "updatedAt": Timestamp(date: date),
                    "deletedAt": Timestamp(date: date),
                ],
                merge: false
            )
    }

    private static func mapComment(_ document: QueryDocumentSnapshot) -> TaskComment? {
        let data = document.data()
        guard let id = UUID(uuidString: (data["id"] as? String) ?? document.documentID) else {
            return nil
        }
        guard let authorUID = data["authorUID"] as? String, !authorUID.isEmpty else {
            return nil
        }
        let display = (data["authorDisplayName"] as? String) ?? authorUID
        let body = (data["body"] as? String) ?? ""
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
        let deletedAt = (data["deletedAt"] as? Timestamp)?.dateValue()
        return TaskComment(
            id: id,
            authorUID: authorUID,
            authorDisplayName: display,
            body: body,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    private func resolveRootTaskID(projectID: UUID, taskID: UUID) async throws -> UUID {
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        var current = taskID
        while true {
            let snap = try await db.collection("projects").document(remoteID)
                .collection("tasks").document(current.uuidString)
                .getDocument()
            guard let parentRaw = snap.data()?["parentTaskId"] as? String,
                  let parentID = UUID(uuidString: parentRaw) else {
                return current
            }
            current = parentID
        }
    }
}
