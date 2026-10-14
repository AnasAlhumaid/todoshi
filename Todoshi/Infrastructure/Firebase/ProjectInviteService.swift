import Foundation
import FirebaseAuth
import FirebaseFirestore
import TodoshiCore

struct ProjectInvitePreview: Sendable, Equatable {
    let token: String
    let projectId: String
    let projectTitle: String
    let inviterDisplayName: String?
    let status: ProjectInviteStatus
}

struct CreatedProjectInvite: Sendable, Equatable {
    let token: String
    let url: URL
    let shareMessage: String
}

struct JoinedProjectRemoteMetadata: Sendable, Equatable {
    let projectID: UUID
    let title: String
    let description: String
    let color: String
    let ownerId: String
    let projectType: ProjectType
}

/// Creates, previews, accepts, and revokes capability-style project invites.
final class ProjectInviteService: Sendable {
    static let shared = ProjectInviteService()

    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    var isConfigured: Bool {
        FirebaseBootstrap.isConfigured
    }

    func createInvite(
        projectID: UUID,
        projectTitle: String,
        inviterDisplayName: String?
    ) async throws -> CreatedProjectInvite {
        guard isConfigured else { throw CollaborationError.notConfigured }
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            throw CollaborationError.notAuthenticated
        }

        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        let title = FieldValidation.trimmed(projectTitle)
        guard !title.isEmpty, title.count <= SharedProjectBootstrapInputValidation.titleMaxLength else {
            throw CollaborationError.inviteCreateFailed
        }

        let token = ProjectInviteTokenGenerator.generate()
        guard let url = ProjectInviteURLBuilder.url(token: token) else {
            throw CollaborationError.inviteCreateFailed
        }

        let displayName = normalizedDisplayName(inviterDisplayName)
        let expiresAt = Timestamp(date: ProjectInviteLifetimePolicy.expiresAt())

        do {
            try await db.collection(FirebaseInviteSecurityPolicy.collectionName).document(token).setData([
                "projectId": remoteID,
                "createdBy": uid,
                "role": ProjectMemberRole.member.rawValue,
                "projectTitle": title,
                "inviterDisplayName": displayName.map { $0 as Any } ?? NSNull(),
                "createdAt": FieldValue.serverTimestamp(),
                "expiresAt": expiresAt,
                "acceptedAt": NSNull(),
                "acceptedBy": NSNull(),
                "revokedAt": NSNull(),
            ])
            return CreatedProjectInvite(
                token: token,
                url: url,
                shareMessage: ProjectInviteURLBuilder.shareMessage(url: url)
            )
        } catch {
            if isPermissionDenied(error) {
                throw CollaborationError.inviteNotOwner
            }
            throw CollaborationError.inviteCreateFailed
        }
    }

    func fetchPreview(token: String) async throws -> ProjectInvitePreview {
        guard isConfigured else { throw CollaborationError.notConfigured }
        guard Auth.auth().currentUser != nil else {
            throw CollaborationError.notAuthenticated
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ProjectInviteTokenGenerator.isValidFormat(trimmed) else {
            throw CollaborationError.inviteInvalid
        }

        do {
            let snap = try await db.collection(FirebaseInviteSecurityPolicy.collectionName)
                .document(trimmed)
                .getDocument()
            guard snap.exists, let data = snap.data() else {
                throw CollaborationError.inviteInvalid
            }
            return try mapPreview(token: trimmed, data: data)
        } catch let error as CollaborationError {
            throw error
        } catch {
            if isPermissionDenied(error) {
                throw CollaborationError.inviteInvalid
            }
            throw CollaborationError.inviteInvalid
        }
    }

    enum AcceptResult: Sendable, Equatable {
        case joined(JoinedProjectRemoteMetadata)
        case alreadyMember(JoinedProjectRemoteMetadata)
    }

    func acceptInvite(token: String, displayName: String?) async throws -> AcceptResult {
        guard isConfigured else { throw CollaborationError.notConfigured }
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            throw CollaborationError.notAuthenticated
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ProjectInviteTokenGenerator.isValidFormat(trimmed) else {
            throw CollaborationError.inviteInvalid
        }

        let preview = try await fetchPreview(token: trimmed)
        switch preview.status {
        case .expired: throw CollaborationError.inviteExpired
        case .accepted: throw CollaborationError.inviteAlreadyUsed
        case .revoked: throw CollaborationError.inviteRevoked
        case .invalid: throw CollaborationError.inviteInvalid
        case .valid: break
        }

        let projectRef = db.collection("projects").document(preview.projectId)
        let memberRef = projectRef.collection("members").document(uid)

        if let existing = try await loadMembershipIfPresent(memberRef: memberRef), existing {
            let meta = try await loadProjectMetadata(projectRef: projectRef, fallbackTitle: preview.projectTitle)
            return .alreadyMember(meta)
        }

        let batch = db.batch()
        batch.updateData(
            [
                "acceptedBy": uid,
                "acceptedAt": FieldValue.serverTimestamp(),
            ],
            forDocument: db.collection(FirebaseInviteSecurityPolicy.collectionName).document(trimmed)
        )
        batch.setData(
            [
                "userId": uid,
                "role": ProjectMemberRole.member.rawValue,
                "displayName": normalizedDisplayName(displayName).map { $0 as Any } ?? NSNull(),
                "joinedAt": FieldValue.serverTimestamp(),
                "acceptedInviteId": trimmed,
                "accessLevel": ProjectMemberAccessLevel.inviteDefault.rawValue,
            ],
            forDocument: memberRef
        )
        batch.updateData(
            [
                "memberIds": FieldValue.arrayUnion([uid]),
            ],
            forDocument: projectRef
        )

        do {
            try await batch.commit()
            let meta = try await loadProjectMetadata(projectRef: projectRef, fallbackTitle: preview.projectTitle)
            return .joined(meta)
        } catch {
            // Race: another device may have joined, or invite became invalid.
            if let joined = try? await loadMembershipIfPresent(memberRef: memberRef), joined {
                let meta = try await loadProjectMetadata(projectRef: projectRef, fallbackTitle: preview.projectTitle)
                return .alreadyMember(meta)
            }
            if isPermissionDenied(error) {
                // Re-fetch invite for a precise status if possible.
                if let refreshed = try? await fetchPreview(token: trimmed) {
                    switch refreshed.status {
                    case .expired: throw CollaborationError.inviteExpired
                    case .accepted: throw CollaborationError.inviteAlreadyUsed
                    case .revoked: throw CollaborationError.inviteRevoked
                    case .invalid, .valid: break
                    }
                }
                throw CollaborationError.inviteAcceptFailed
            }
            throw CollaborationError.inviteAcceptFailed
        }
    }

    func revokeInvite(token: String) async throws {
        guard isConfigured else { throw CollaborationError.notConfigured }
        guard Auth.auth().currentUser != nil else {
            throw CollaborationError.notAuthenticated
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ProjectInviteTokenGenerator.isValidFormat(trimmed) else {
            throw CollaborationError.inviteInvalid
        }
        do {
            try await db.collection(FirebaseInviteSecurityPolicy.collectionName)
                .document(trimmed)
                .updateData(["revokedAt": FieldValue.serverTimestamp()])
        } catch {
            if isPermissionDenied(error) {
                throw CollaborationError.inviteNotOwner
            }
            throw CollaborationError.inviteCreateFailed
        }
    }

    /// Discovers remote projects via memberIds index (list rule); membership still gates get/content.
    func discoverJoinedProjectIDs(uid: String) async throws -> [String] {
        guard isConfigured else { throw CollaborationError.notConfigured }
        guard FirebaseIdentifierPolicy.isValidFirebaseUserID(uid) else {
            throw CollaborationError.notAuthenticated
        }
        do {
            let snapshot = try await db.collection("projects")
                .whereField("memberIds", arrayContains: uid)
                .getDocuments()
            return snapshot.documents.map(\.documentID)
        } catch {
            throw CollaborationError.membersLoadFailed
        }
    }

    private func mapPreview(token: String, data: [String: Any]) throws -> ProjectInvitePreview {
        guard let projectId = data["projectId"] as? String,
              !projectId.isEmpty,
              let projectTitle = data["projectTitle"] as? String
        else {
            throw CollaborationError.inviteInvalid
        }
        let acceptedBy = data["acceptedBy"] as? String
        let revokedAt = (data["revokedAt"] as? Timestamp)?.dateValue()
        let expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue()
        let status = ProjectInviteStatusPolicy.status(
            acceptedBy: acceptedBy,
            revokedAt: revokedAt,
            expiresAt: expiresAt
        )
        return ProjectInvitePreview(
            token: token,
            projectId: projectId,
            projectTitle: projectTitle,
            inviterDisplayName: data["inviterDisplayName"] as? String,
            status: status
        )
    }

    private func loadMembershipIfPresent(memberRef: DocumentReference) async throws -> Bool? {
        do {
            let snap = try await memberRef.getDocument()
            return snap.exists ? true : nil
        } catch {
            if isPermissionDenied(error) {
                return nil
            }
            throw CollaborationError.inviteAcceptFailed
        }
    }

    private func loadProjectMetadata(
        projectRef: DocumentReference,
        fallbackTitle: String
    ) async throws -> JoinedProjectRemoteMetadata {
        let snap = try await projectRef.getDocument()
        guard let data = snap.data(),
              let idString = (data["id"] as? String) ?? Optional(projectRef.documentID),
              let projectID = UUID(uuidString: idString),
              let ownerId = data["ownerId"] as? String
        else {
            throw CollaborationError.inviteAcceptFailed
        }
        let title = (data["title"] as? String).flatMap {
            let t = FieldValidation.trimmed($0)
            return t.isEmpty ? nil : t
        } ?? fallbackTitle
        let description = FieldValidation.trimmed((data["description"] as? String) ?? "")
        let color = ProjectColorCatalog.sanitized((data["color"] as? String) ?? ProjectColorCatalog.defaultHex)
        return JoinedProjectRemoteMetadata(
            projectID: projectID,
            title: title,
            description: description,
            color: color,
            ownerId: ownerId,
            projectType: ProjectType.resolve(data["projectType"] as? String)
        )
    }

    private func normalizedDisplayName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = FieldValidation.trimmed(value)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(80))
    }

    private func isPermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == FirestoreErrorDomain
            && nsError.code == FirestoreErrorCode.permissionDenied.rawValue
    }
}
