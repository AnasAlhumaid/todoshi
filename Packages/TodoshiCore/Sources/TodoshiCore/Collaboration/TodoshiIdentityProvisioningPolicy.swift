import Foundation

public enum TodoshiIdentityTransactionDecision: Equatable, Sendable {
    case useExisting(String)
    case commitCandidate(String)
    case retryCollision
}

/// Pure decision logic for transactional Todoshi ID provisioning.
public enum TodoshiIdentityProvisioningPolicy: Sendable {
    public static func shouldProvision(existingTodoshiId: String?) -> Bool {
        normalized(existingTodoshiId) == nil
    }

    public static func decide(
        existingUserTodoshiId: String?,
        candidate: String,
        claimExists: Bool,
        claimUID: String?,
        actingUID: String
    ) -> TodoshiIdentityTransactionDecision {
        if let existing = normalized(existingUserTodoshiId) {
            return .useExisting(existing)
        }
        guard TodoshiIDPolicy.isValid(candidate) else {
            return .retryCollision
        }
        if claimExists {
            if claimUID == actingUID {
                return .commitCandidate(candidate)
            }
            return .retryCollision
        }
        return .commitCandidate(candidate)
    }

    /// Same Firebase UID must always resolve to the same Todoshi ID once provisioned.
    public static func resolvedIdentity(
        existingUserTodoshiId: String?,
        publicIdentityTodoshiId: String?
    ) -> String? {
        normalized(existingUserTodoshiId) ?? normalized(publicIdentityTodoshiId)
    }

    public static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TodoshiIDPolicy.isValid(trimmed) else { return nil }
        return trimmed
    }
}

public enum TodoshiIdentityPresentationPolicy: Sendable {
    /// Owner Member Detail only for this release.
    public static func showsMemberTodoshiID(isOwnerManagingMember: Bool) -> Bool {
        isOwnerManagingMember
    }

    public static func showsOwnTodoshiIDInProfile(isSignedIn: Bool) -> Bool {
        isSignedIn
    }
}
