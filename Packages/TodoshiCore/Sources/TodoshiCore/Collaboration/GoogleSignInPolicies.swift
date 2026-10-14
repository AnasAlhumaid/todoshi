import Foundation

/// Collaboration membership always keys on Firebase Auth UID — never email or provider subject IDs.
public enum CollaborationIdentityAuthorityPolicy: Sendable {
    public static let membershipDocumentID = "Firebase Auth UID"

    public static func isValidMembershipUserID(_ value: String) -> Bool {
        FirebaseIdentifierPolicy.isValidFirebaseUserID(value)
    }

    /// Apple / Google provider identifiers must never authorize project membership.
    public static func rejectsProviderSubjectAsMembershipID(_ providerSubject: String) -> Bool {
        // Provider subjects are opaque and must not be treated as Firebase UIDs for membership paths.
        // Membership paths always use Auth.auth().currentUser.uid after Firebase credential exchange.
        !providerSubject.isEmpty
    }
}

/// Provider linking (Apple + Google on one Firebase user) is deferred.
public enum AuthProviderLinkingPolicy: Sendable {
    public static let automaticMergeAllowed = false
    public static let connectedAccountsUIEnabled = false

    /// Future: `Auth.auth().currentUser?.link(with:)` after the user signs in with their existing method.
    public static let deferredStrategy = """
    Do not auto-merge accounts. If Firebase reports accountExistsWithDifferentCredential / \
    emailAlreadyInUse / credentialAlreadyInUse, ask the user to sign in with the existing method first, \
    then offer explicit provider linking via currentUser.link(with:) in a later Connected Accounts phase.
    """
}

public enum GoogleSignInErrorPolicy: Sendable {
    /// `GIDSignInError.canceled`
    public static let canceledCode = -5
    public static let googleSignInErrorDomain = "com.google.GIDSignIn"

    public static func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == googleSignInErrorDomain && nsError.code == canceledCode {
            return true
        }
        // Some SDK versions surface cancellation via localized description only — keep domain/code primary.
        return false
    }

    public static func collaborationError(for error: Error) -> CollaborationError {
        if isUserCancellation(error) {
            return .signInCancelled
        }
        return .googleSignInFailed
    }
}
