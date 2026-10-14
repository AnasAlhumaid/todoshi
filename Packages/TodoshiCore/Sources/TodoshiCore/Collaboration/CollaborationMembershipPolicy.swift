import Foundation

/// Membership authorization policy for shared Firebase projects.
public enum CollaborationMembershipPolicy: Sendable {
    /// `projects/{projectId}/members/{uid}` is the sole authorization authority.
    public static let membershipDocumentIsAuthority = true

    /// `projects.memberIds[]` must never by itself grant access to project contents.
    public static let memberIdsGrantsAuthorization = false

    public static let membershipDocumentPathPattern =
        "projects/{projectId}/members/{uid}"

    public static let memberIdsQueryPattern =
        "projects where memberIds arrayContains currentUser.uid"

    /// When representations diverge, membership documents control authorization.
    public static let divergenceFailureBehavior =
        "Membership document controls authorization; memberIds does not grant additional privileges."
}
