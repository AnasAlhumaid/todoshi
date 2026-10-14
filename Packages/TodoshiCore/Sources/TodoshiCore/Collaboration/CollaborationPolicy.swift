import Foundation

public enum CollaborationError: Error, Sendable, Equatable {
    case notConfigured
    case notAuthenticated
    case unavailable
    case signInCancelled
    case appleCredentialUnavailable
    case missingIdentityToken
    case invalidCredential
    case signInFailed
    case googleCredentialUnavailable
    case googlePresentationFailed
    case googleSignInFailed
    case accountExistsWithDifferentCredential
    case profileSyncFailed
    case profileLoadFailed
    case profileNameInvalid
    case profileNameTooLong
    case profileUpdateFailed
    case shareConversionDisabled
    case shareFailed
    case shareLocalSaveFailed
    case shareConflict
    case alreadyShared
    case membersLoadFailed
    case inviteInvalid
    case inviteExpired
    case inviteAlreadyUsed
    case inviteRevoked
    case inviteCreateFailed
    case inviteAcceptFailed
    case inviteNotOwner
    case commentInvalidBody
    case commentPostFailed
    case taskEditPermissionDenied
    case memberRemoveFailed
    case memberLeaveFailed
    case identityProvisioningFailed
    case accountDeletionFailed
    case accountDeletionRequiresReauthentication
    case accountDeletionCancelled
    case accountDeletionProviderRevokeFailed
    case accountDeletionTimedOut
}

public enum CollaborationArchitecturePolicy: Sendable {
    public static let personalProjectSourceOfTruth = "SwiftData"
    public static let sharedProjectSourceOfTruth = "Firestore"

    /// Personal projects remain fully local; shared projects use Firestore as collaboration authority.
    public static func sourceOfTruth(isShared: Bool) -> String {
        isShared ? sharedProjectSourceOfTruth : personalProjectSourceOfTruth
    }
}

public enum CollaborationConfigurationStatus: Sendable, Equatable {
    case unavailable
    case configuredLocalOnly
    case configuredWithBackend
}

public enum CollaborationConfigurationPolicy: Sendable {
    /// Reports whether collaboration features can be used without crashing when Firebase is absent.
    public static func status(isFirebaseConfigured: Bool) -> CollaborationConfigurationStatus {
        isFirebaseConfigured ? .configuredWithBackend : .configuredLocalOnly
    }

    /// Local-only mode must remain fully functional without Firebase network access.
    public static var localOnlyGuarantee: Bool { true }
}
