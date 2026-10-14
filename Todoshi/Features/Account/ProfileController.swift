import Foundation
import Observation
import TodoshiCore

@Observable
@MainActor
final class ProfileController {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case unavailable
    }

    private(set) var loadState: LoadState = .idle
    private(set) var profile: CollaborationProfile?
    private(set) var isSaving = false
    var statusMessage: String?

    private let service: ProfileService

    init(service: ProfileService = .shared) {
        self.service = service
    }

    func load(uid: String, preferServer: Bool = false) async {
        loadState = .loading
        statusMessage = nil
        do {
            profile = try await service.loadProfile(uid: uid, preferServer: preferServer)
            loadState = .loaded
        } catch {
            loadState = .unavailable
            statusMessage = UserFacingError.message(for: CollaborationError.profileLoadFailed)
            TodoshiDiagnostics.failure("profile_load")
        }
    }

    func save(uid: String, displayNameRaw: String) async -> Bool {
        guard let current = profile else {
            statusMessage = UserFacingError.message(for: CollaborationError.profileLoadFailed)
            return false
        }
        guard !isSaving else { return false }

        isSaving = true
        statusMessage = nil
        defer { isSaving = false }

        do {
            profile = try await service.saveDisplayName(
                uid: uid,
                current: current,
                displayNameRaw: displayNameRaw
            )
            return true
        } catch {
            statusMessage = UserFacingError.message(for: error)
            return false
        }
    }

    func applySessionFallback(_ session: CollaborationSession) {
        if profile == nil {
            profile = CollaborationProfile(
                userID: session.user.id,
                displayName: session.user.displayName,
                email: session.user.email,
                avatarPath: nil
            )
        }
    }

    func applyTodoshiID(_ todoshiId: String?) {
        guard let todoshiId,
              let normalized = TodoshiIdentityProvisioningPolicy.normalized(todoshiId),
              let profile else { return }
        self.profile = TodoshiIdentitySessionPolicy.mergedProfile(profile, todoshiId: normalized)
    }
}
