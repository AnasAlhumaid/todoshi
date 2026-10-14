import Foundation
import Testing
@testable import TodoshiCore

@Suite("Google Authentication Phase 1.2")
struct PhaseGoogleAuthTests {
    @Test("Google auth maps to CollaborationSession via Firebase UID")
    func googleMapsToCollaborationSession() {
        let session = CollaborationSessionMapper.session(
            from: CollaborationSessionMapper.UserInput(
                id: "firebase-google-uid-1",
                displayName: "Anas Hamad",
                email: "anas@example.com"
            )
        )
        #expect(session?.user.id == "firebase-google-uid-1")
        #expect(session?.user.displayName == "Anas Hamad")
        #expect(session?.user.email == "anas@example.com")
        #expect(UUID(uuidString: session!.user.id) == nil)
    }

    @Test("Firebase UID remains collaboration identity authority")
    func firebaseUIDIsMembershipAuthority() {
        #expect(CollaborationIdentityAuthorityPolicy.membershipDocumentID == "Firebase Auth UID")
        #expect(CollaborationIdentityAuthorityPolicy.isValidMembershipUserID("abc123"))
        #expect(AuthProviderLinkingPolicy.automaticMergeAllowed == false)
        #expect(AuthProviderLinkingPolicy.connectedAccountsUIEnabled == false)
        #expect(AuthProviderLinkingPolicy.deferredStrategy.contains("link(with:)"))
    }

    @Test("Google display name and email map into profile merge policy")
    func googleProfileMerge() {
        let payload = FirestoreUserProfilePayloadPolicy.payload(
            existing: nil,
            incoming: FirebaseUserProfileFields(
                displayName: "Anas Hamad",
                email: "anas@example.com"
            ),
            documentExists: false
        )
        #expect(payload.displayName == "Anas Hamad")
        #expect(payload.email == "anas@example.com")
        #expect(payload.includeCreatedAt == true)

        let initials = ProfileAvatarInitialsPolicy.initials(from: "Anas Hamad")
        #expect(initials == "AH")
    }

    @Test("Google cancellation is non-fatal")
    func googleCancellationNonFatal() {
        let canceled = NSError(
            domain: GoogleSignInErrorPolicy.googleSignInErrorDomain,
            code: GoogleSignInErrorPolicy.canceledCode
        )
        #expect(GoogleSignInErrorPolicy.isUserCancellation(canceled))
        #expect(GoogleSignInErrorPolicy.collaborationError(for: canceled) == .signInCancelled)
        let outcome = AuthSessionFlowPolicy.outcome(
            authenticatedSession: nil,
            signInError: CollaborationError.signInCancelled,
            profileSyncFailed: false
        )
        #expect(outcome == .signedOutWithError)
        #expect(CollaborationArchitecturePolicy.personalProjectSourceOfTruth == "SwiftData")
    }

    @Test("Missing Google ID token fails safely")
    func missingGoogleIDTokenFailsSafely() {
        #expect(UserFacingError.message(for: CollaborationError.missingIdentityToken).isEmpty == false)
        #expect(
            UserFacingError.message(
                for: CollaborationError.googleCredentialUnavailable,
                locale: Locale(identifier: "en")
            ).contains("Google")
        )
    }

    @Test("Provider collision maps to safe user-facing error")
    func providerCollisionMapping() {
        let collision = NSError(
            domain: FirebaseAuthErrorPolicy.errorDomain,
            code: FirebaseAuthErrorPolicy.accountExistsWithDifferentCredentialCode,
            userInfo: [FirebaseAuthErrorPolicy.errorNameKey: "ERROR_ACCOUNT_EXISTS_WITH_DIFFERENT_CREDENTIAL"]
        )
        #expect(
            FirebaseAuthErrorPolicy.classify(collision) == .accountExistsWithDifferentCredential
        )
        #expect(
            FirebaseAuthErrorPolicy.collaborationError(for: collision)
                == .accountExistsWithDifferentCredential
        )
        let en = UserFacingError.message(
            for: CollaborationError.accountExistsWithDifferentCredential,
            locale: Locale(identifier: "en")
        )
        let ar = UserFacingError.message(
            for: CollaborationError.accountExistsWithDifferentCredential,
            locale: Locale(identifier: "ar")
        )
        #expect(en.contains("another sign-in method"))
        #expect(ar.isEmpty == false)
    }

    @Test("Signed-out auth gate remains unchanged")
    func signedOutGateUnchanged() {
        #expect(CollaborationAuthGate.requirement(for: nil) == .requiresAuthentication)
    }

    @Test("Signed-in Google session satisfies collaboration gate")
    func googleSessionSatisfiesGate() {
        let session = CollaborationSession(
            user: CollaborationUser(
                id: "google-backed-firebase-uid",
                displayName: "Anas",
                email: "a@b.com"
            )
        )
        #expect(CollaborationAuthGate.requirement(for: session) == .authenticated(session))
    }

    @Test("Local-only use is unaffected")
    func localOnlyUnaffected() {
        #expect(CollaborationConfigurationPolicy.localOnlyGuarantee == true)
        #expect(
            CollaborationConfigurationPolicy.status(isFirebaseConfigured: false)
                == .configuredLocalOnly
        )
        #expect(CollaborationArchitecturePolicy.sourceOfTruth(isShared: false) == "SwiftData")
    }

    @Test("Apple authentication error mapping remains available")
    func appleMappingPreserved() {
        #expect(UserFacingError.message(for: CollaborationError.signInCancelled).isEmpty == false)
        #expect(
            UserFacingError.message(for: CollaborationError.appleCredentialUnavailable).isEmpty
                == false
        )
        let nonceError = NSError(
            domain: FirebaseAuthErrorPolicy.errorDomain,
            code: FirebaseAuthErrorPolicy.missingOrInvalidNonceCode,
            userInfo: [FirebaseAuthErrorPolicy.errorNameKey: "ERROR_MISSING_OR_INVALID_NONCE"]
        )
        #expect(FirebaseAuthErrorPolicy.isMissingOrInvalidNonce(nonceError))
    }
}
