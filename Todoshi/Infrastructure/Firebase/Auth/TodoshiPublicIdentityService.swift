import Foundation
import FirebaseFirestore
import TodoshiCore

/// Owner lookup of a member's stable Todoshi ID via `publicIdentities/{uid}`.
final class TodoshiPublicIdentityService: Sendable {
    static let shared = TodoshiPublicIdentityService()

    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchPublicIdentity(for memberUID: String) async throws -> TodoshiPublicIdentity? {
        guard FirebaseBootstrap.isConfigured else {
            throw CollaborationError.notConfigured
        }

        let snapshot = try await db.collection("publicIdentities").document(memberUID).getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }

        guard
            let userID = data["userId"] as? String,
            let todoshiId = TodoshiIdentityProvisioningPolicy.normalized(data["todoshiId"] as? String),
            userID == memberUID
        else {
            return nil
        }

        return TodoshiPublicIdentity(
            userID: userID,
            todoshiId: todoshiId,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }
}
