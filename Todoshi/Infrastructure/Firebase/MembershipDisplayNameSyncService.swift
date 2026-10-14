import Foundation
import FirebaseFirestore
import TodoshiCore

/// Propagates `users/{uid}.displayName` to the current user's membership snapshots in shared projects.
@MainActor
final class MembershipDisplayNameSyncService {
    static let shared = MembershipDisplayNameSyncService()

    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    var isConfigured: Bool {
        FirebaseBootstrap.isConfigured
    }

    /// After a profile rename — update every current membership document for this user.
    func propagateDisplayName(uid: String, displayName: String) async throws {
        guard isConfigured else { return }
        guard let normalized = CollaborationDisplayNamePolicy.normalized(displayName) else { return }
        let projectIDs = try await ProjectInviteService.shared.discoverJoinedProjectIDs(uid: uid)
        try await updateMemberships(
            uid: uid,
            profileName: normalized,
            projectRemoteIDs: projectIDs
        )
    }

    /// Session-restore repair for memberships that still carry a stale name snapshot.
    func repairStaleMembershipsIfNeeded(uid: String, profileDisplayName: String) async {
        guard isConfigured else { return }
        guard let normalized = CollaborationDisplayNamePolicy.normalized(profileDisplayName) else { return }
        do {
            let projectIDs = try await ProjectInviteService.shared.discoverJoinedProjectIDs(uid: uid)
            try await updateMemberships(
                uid: uid,
                profileName: normalized,
                projectRemoteIDs: projectIDs
            )
        } catch {
            #if DEBUG
            TodoshiDiagnostics.note("[Profile] membership name repair failed")
            #endif
        }
    }

    private func updateMemberships(
        uid: String,
        profileName: String,
        projectRemoteIDs: [String]
    ) async throws {
        var lastError: Error?
        for remoteID in projectRemoteIDs {
            do {
                try await updateMembershipIfNeeded(
                    uid: uid,
                    profileName: profileName,
                    projectRemoteID: remoteID
                )
            } catch {
                lastError = error
                #if DEBUG
                TodoshiDiagnostics.note("[Profile] membership update failed project=\(remoteID.prefix(8))")
                #endif
            }
        }
        if let lastError, projectRemoteIDs.count == 1 {
            throw lastError
        }
    }

    private func updateMembershipIfNeeded(
        uid: String,
        profileName: String,
        projectRemoteID: String
    ) async throws {
        let ref = db.collection("projects")
            .document(projectRemoteID)
            .collection("members")
            .document(uid)
        let snap = try await ref.getDocument()
        guard snap.exists, let data = snap.data() else { return }
        let membershipName = data["displayName"] as? String
        guard MemberDisplayNamePropagationPolicy.shouldUpdate(
            profileName: profileName,
            membershipName: membershipName
        ) else { return }
        try await ref.updateData(["displayName": profileName])
    }
}
