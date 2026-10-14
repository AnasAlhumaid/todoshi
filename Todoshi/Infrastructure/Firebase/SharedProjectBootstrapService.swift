import Foundation
import FirebaseAuth
import FirebaseFirestore
import TodoshiCore

struct SharedProjectBootstrapPayload: Sendable {
    let projectID: UUID
    let title: String
    let description: String
    let color: String
    let displayName: String?
    let projectType: ProjectType

    init(
        projectID: UUID,
        title: String,
        description: String,
        color: String,
        displayName: String?,
        projectType: ProjectType = .tasks
    ) {
        self.projectID = projectID
        self.title = title
        self.description = description
        self.color = color
        self.displayName = displayName
        self.projectType = projectType
    }
}

enum SharedProjectBootstrapResult: Sendable, Equatable {
    case created
    case repaired
}

/// Firestore-only shared-project bootstrap via atomic WriteBatch.
/// Never marks local SwiftData state; caller applies metadata after success.
final class FirestoreSharedProjectBootstrapService: Sendable {
    static let shared = FirestoreSharedProjectBootstrapService()

    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    var isConfigured: Bool {
        FirebaseBootstrap.isConfigured
    }

    func createSharedProject(_ payload: SharedProjectBootstrapPayload) async throws -> SharedProjectBootstrapResult {
        guard SharedProjectBootstrapPolicy.isShareConversionEnabled else {
            throw CollaborationError.shareConversionDisabled
        }
        guard isConfigured else {
            throw CollaborationError.notConfigured
        }
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            throw CollaborationError.notAuthenticated
        }

        let validated = SharedProjectBootstrapInputValidation.validate(
            projectID: payload.projectID.uuidString,
            title: payload.title,
            description: payload.description,
            color: payload.color
        )
        guard case .success(let values) = validated else {
            throw CollaborationError.shareFailed
        }
        let (projectUUID, title, description, color) = values
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectUUID)
        let projectRef = db.collection("projects").document(remoteID)
        let memberRef = projectRef.collection("members").document(uid)

        if let existing = try await loadOwnedBootstrapIfPresent(
            projectRef: projectRef,
            memberRef: memberRef,
            ownerUID: uid
        ) {
            return existing
        }

        let displayName = normalizedDisplayName(payload.displayName)
        let batch = db.batch()
        batch.setData(
            [
                "id": remoteID,
                "ownerId": uid,
                "title": title,
                "description": description,
                "color": color,
                "memberIds": [uid],
                "projectType": payload.projectType.rawValue,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
                "deletedAt": NSNull(),
            ],
            forDocument: projectRef
        )
        batch.setData(
            [
                "userId": uid,
                "role": ProjectMemberRole.owner.rawValue,
                "displayName": displayName.map { $0 as Any } ?? NSNull(),
                "joinedAt": FieldValue.serverTimestamp(),
                "accessLevel": ProjectMemberAccessLevel.full.rawValue,
            ],
            forDocument: memberRef
        )

        do {
            try await batch.commit()
            return .created
        } catch {
            // Retry path: remote may already exist from a prior successful commit.
            if let repaired = try await loadOwnedBootstrapIfPresent(
                projectRef: projectRef,
                memberRef: memberRef,
                ownerUID: uid
            ) {
                return repaired
            }
            if isPermissionDenied(error) {
                throw CollaborationError.shareConflict
            }
            throw CollaborationError.shareFailed
        }
    }

    private func loadOwnedBootstrapIfPresent(
        projectRef: DocumentReference,
        memberRef: DocumentReference,
        ownerUID: String
    ) async throws -> SharedProjectBootstrapResult? {
        do {
            let projectSnap = try await projectRef.getDocument()
            guard projectSnap.exists, let data = projectSnap.data() else {
                return nil
            }
            guard (data["ownerId"] as? String) == ownerUID else {
                throw CollaborationError.shareConflict
            }

            let memberSnap = try await memberRef.getDocument()
            guard memberSnap.exists,
                  let memberData = memberSnap.data(),
                  (memberData["userId"] as? String) == ownerUID,
                  (memberData["role"] as? String) == ProjectMemberRole.owner.rawValue
            else {
                throw CollaborationError.shareFailed
            }
            return .repaired
        } catch let error as CollaborationError {
            throw error
        } catch {
            if isPermissionDenied(error) {
                // Unreadable: either absent (create next) or owned by someone else.
                return nil
            }
            throw CollaborationError.shareFailed
        }
    }

    private func normalizedDisplayName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = FieldValidation.trimmed(value)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isPermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == FirestoreErrorDomain
            && nsError.code == FirestoreErrorCode.permissionDenied.rawValue
    }
}

typealias SharedProjectBootstrapService = FirestoreSharedProjectBootstrapService
