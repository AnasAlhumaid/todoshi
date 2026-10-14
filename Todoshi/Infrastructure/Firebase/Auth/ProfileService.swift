import Foundation
import TodoshiCore

@MainActor
final class ProfileService {
    static let shared = ProfileService()

    private let firestore: FirestoreUserProfileService
    private let authService: FirebaseAuthService
    private let membershipSync: MembershipDisplayNameSyncService

    init(
        firestore: FirestoreUserProfileService = .shared,
        authService: FirebaseAuthService = .shared,
        membershipSync: MembershipDisplayNameSyncService = .shared
    ) {
        self.firestore = firestore
        self.authService = authService
        self.membershipSync = membershipSync
    }

    func loadProfile(uid: String, preferServer: Bool = false) async throws -> CollaborationProfile {
        do {
            return try await firestore.loadProfile(uid: uid, preferServer: preferServer)
        } catch let error as CollaborationError {
            throw error
        } catch {
            throw CollaborationError.profileLoadFailed
        }
    }

    func saveDisplayName(
        uid: String,
        current: CollaborationProfile,
        displayNameRaw: String
    ) async throws -> CollaborationProfile {
        let displayName: String
        switch ProfileDisplayNameValidation.validated(displayNameRaw) {
        case .success(let value):
            displayName = value
        case .failure(.empty):
            throw CollaborationError.profileNameInvalid
        case .failure(.tooLong):
            throw CollaborationError.profileNameTooLong
        }

        do {
            try await firestore.updateEditableProfile(
                uid: uid,
                displayName: displayName,
                email: current.email
            )
            await authService.updateDisplayName(uid: uid, displayName: displayName)
            do {
                try await membershipSync.propagateDisplayName(uid: uid, displayName: displayName)
            } catch {
                #if DEBUG
                TodoshiDiagnostics.note("[Profile] membership propagation failed after profile save")
                #endif
            }
            return CollaborationProfile(
                userID: uid,
                displayName: displayName,
                email: current.email,
                avatarPath: current.avatarPath,
                todoshiId: current.todoshiId
            )
        } catch let error as CollaborationError {
            throw error
        } catch {
            throw CollaborationError.profileUpdateFailed
        }
    }
}
