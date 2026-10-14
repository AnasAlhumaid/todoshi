import Foundation

public enum AuthSessionFlowPolicy: Sendable {
    public enum Outcome: Sendable, Equatable {
        case signedOutWithError
        case signedIn(profileSyncWarning: Bool)
    }

    /// Firebase Auth session is authoritative; profile sync must not revoke it.
    public static func outcome(
        authenticatedSession: CollaborationSession?,
        signInError: Error?,
        profileSyncFailed: Bool
    ) -> Outcome {
        if authenticatedSession != nil {
            return .signedIn(profileSyncWarning: profileSyncFailed)
        }
        if signInError != nil {
            return .signedOutWithError
        }
        return .signedOutWithError
    }
}
