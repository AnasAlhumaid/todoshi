import Foundation

/// Keeps authenticated profile/session presentation aligned with canonical Todoshi ID state.
public enum TodoshiIdentitySessionPolicy: Sendable {
    public static func resolvedTodoshiId(
        profileTodoshiId: String?,
        sessionTodoshiId: String?
    ) -> String? {
        TodoshiIdentityProvisioningPolicy.normalized(profileTodoshiId)
            ?? TodoshiIdentityProvisioningPolicy.normalized(sessionTodoshiId)
    }

    public static func mergedProfile(
        _ profile: CollaborationProfile,
        todoshiId: String
    ) -> CollaborationProfile {
        guard let normalized = TodoshiIdentityProvisioningPolicy.normalized(todoshiId) else {
            return profile
        }
        var updated = profile
        updated.todoshiId = normalized
        return updated
    }

    public static func shouldReloadProfile(
        profileTodoshiId: String?,
        sessionTodoshiId: String?
    ) -> Bool {
        TodoshiIdentityProvisioningPolicy.normalized(profileTodoshiId) == nil
            && TodoshiIdentityProvisioningPolicy.normalized(sessionTodoshiId) != nil
    }

    public static func shouldClearProvisioningWarning(sessionTodoshiId: String?) -> Bool {
        TodoshiIdentityProvisioningPolicy.normalized(sessionTodoshiId) != nil
    }

    public static func shouldSkipProvisioning(
        cachedSessionTodoshiId: String?,
        canonicalTodoshiId: String?
    ) -> Bool {
        TodoshiIdentityProvisioningPolicy.normalized(cachedSessionTodoshiId) != nil
            || TodoshiIdentityProvisioningPolicy.normalized(canonicalTodoshiId) != nil
    }

    public static func shouldRunProvisioning(
        cachedSessionTodoshiId: String?,
        canonicalTodoshiId: String?
    ) -> Bool {
        !shouldSkipProvisioning(
            cachedSessionTodoshiId: cachedSessionTodoshiId,
            canonicalTodoshiId: canonicalTodoshiId
        )
    }

    public static func shouldRetryProvisioningAfterTask(cachedSessionTodoshiId: String?) -> Bool {
        TodoshiIdentityProvisioningPolicy.normalized(cachedSessionTodoshiId) == nil
    }
}
