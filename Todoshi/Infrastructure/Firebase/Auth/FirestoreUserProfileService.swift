import Foundation
import FirebaseFirestore
import TodoshiCore

@MainActor
final class FirestoreUserProfileService {
    static let shared = FirestoreUserProfileService()

    private init() {}

    func loadProfile(uid: String, preferServer: Bool = false) async throws -> CollaborationProfile {
        guard FirebaseBootstrap.isConfigured else {
            throw CollaborationError.notConfigured
        }

        let ref = Firestore.firestore().collection("users").document(uid)
        let snapshot: DocumentSnapshot
        if preferServer {
            snapshot = try await ref.getDocument(source: .server)
        } else {
            snapshot = try await ref.getDocument()
        }
        let data = snapshot.data() ?? [:]
        return CollaborationProfile(
            userID: uid,
            displayName: data["displayName"] as? String,
            email: data["email"] as? String,
            avatarPath: data["avatarPath"] as? String,
            todoshiId: TodoshiIdentityProvisioningPolicy.normalized(data["todoshiId"] as? String)
        )
    }

    func syncProfile(
        uid: String,
        displayName: String?,
        email: String?
    ) async throws {
        guard FirebaseBootstrap.isConfigured else { return }

        #if DEBUG
        TodoshiDiagnostics.note("[Profile] Firestore profile sync started")
        #endif

        let ref = Firestore.firestore().collection("users").document(uid)

        do {
            let snapshot = try await ref.getDocument()
            let existing = fields(from: snapshot.data())

            let planned = FirestoreUserProfilePayloadPolicy.payload(
                existing: existing,
                incoming: FirebaseUserProfileFields(displayName: displayName, email: email),
                documentExists: snapshot.exists
            )

            try await write(payload: planned, to: ref)

            #if DEBUG
            TodoshiDiagnostics.note("[Profile] Firestore profile sync succeeded")
            #endif
        } catch {
            #if DEBUG
            logProfileSyncFailure(error)
            #endif
            throw error
        }
    }

    /// Updates editable profile fields (display name only in the current MVP).
    func updateEditableProfile(
        uid: String,
        displayName: String,
        email: String?
    ) async throws {
        guard FirebaseBootstrap.isConfigured else {
            throw CollaborationError.notConfigured
        }

        let ref = Firestore.firestore().collection("users").document(uid)
        let snapshot = try await ref.getDocument()
        let existing = fields(from: snapshot.data())

        let planned = FirestoreUserProfilePayloadPolicy.payload(
            existing: existing,
            incoming: FirebaseUserProfileFields(displayName: displayName, email: email),
            documentExists: snapshot.exists
        )

        let forced = FirestoreUserProfilePayloadPolicy.Payload(
            displayName: displayName,
            email: planned.email ?? email,
            includeCreatedAt: planned.includeCreatedAt
        )

        do {
            try await write(payload: forced, to: ref)
        } catch {
            #if DEBUG
            logProfileSyncFailure(error)
            #endif
            throw CollaborationError.profileUpdateFailed
        }
    }

    private func fields(from data: [String: Any]?) -> FirebaseUserProfileFields? {
        guard let data else { return nil }
        return FirebaseUserProfileFields(
            displayName: data["displayName"] as? String,
            email: data["email"] as? String,
            avatarPath: data["avatarPath"] as? String,
            todoshiId: data["todoshiId"] as? String
        )
    }

    private func write(
        payload: FirestoreUserProfilePayloadPolicy.Payload,
        to ref: DocumentReference
    ) async throws {
        var data: [String: Any] = [
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let displayName = payload.displayName {
            data["displayName"] = displayName
        }
        if let email = payload.email {
            data["email"] = email
        }
        // MVP does not write avatarPath. Existing nil/missing values remain harmless.
        if payload.includeCreatedAt {
            data["createdAt"] = FieldValue.serverTimestamp()
        }
        try await ref.setData(data, merge: true)
    }

    #if DEBUG
    private func logProfileSyncFailure(_ error: Error) {
        let info = FirestoreErrorPolicy.debugInfo(for: error)
        TodoshiDiagnostics.note("[Profile] Firestore profile sync failed")
        TodoshiDiagnostics.note("domain=\(info.domain)")
        TodoshiDiagnostics.note("code=\(info.code)")
        TodoshiDiagnostics.note("classification=\(info.classification.rawValue)")
    }
    #endif
}
