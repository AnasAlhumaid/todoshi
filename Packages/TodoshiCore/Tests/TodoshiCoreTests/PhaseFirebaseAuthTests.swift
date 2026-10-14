import Foundation
import Testing
@testable import TodoshiCore

@Suite("Firebase Authentication Phase 1")
struct PhaseFirebaseAuthTests {
    @Test("Signed-out initial gate requires authentication")
    func signedOutGate() {
        let requirement = CollaborationAuthGate.requirement(for: nil)
        #expect(requirement == .requiresAuthentication)
    }

    @Test("Signed-in gate returns collaboration session")
    func signedInGate() {
        let session = CollaborationSession(
            user: CollaborationUser(id: "firebase-uid-123", displayName: "Anas", email: "user@example.com")
        )
        let requirement = CollaborationAuthGate.requirement(for: session)
        #expect(requirement == .authenticated(session))
    }

    @Test("Firebase user maps to CollaborationSession with String UID")
    func sessionMapping() {
        let session = CollaborationSessionMapper.session(
            from: CollaborationSessionMapper.UserInput(
                id: "firebase-uid-abc",
                displayName: "Anas",
                email: "user@example.com"
            )
        )
        #expect(session?.user.id == "firebase-uid-abc")
        #expect(UUID(uuidString: session!.user.id) == nil)
    }

    @Test("Apple nonce generation is non-empty and unique")
    func nonceGeneration() {
        let first = AppleSignInNonce.randomNonce()
        let second = AppleSignInNonce.randomNonce()
        #expect(first.isEmpty == false)
        #expect(second.isEmpty == false)
        #expect(first != second)
    }

    @Test("Apple nonce SHA256 produces lowercase hex")
    func nonceHash() {
        let hash = AppleSignInNonce.sha256("test-nonce")
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit })
        #expect(hash == hash.lowercased())
    }

    @Test("Raw nonce is generated once per attempt and Apple receives SHA256")
    func nonceAttemptLifecycle() {
        let attempt = AppleSignInNonceAttempt.make()
        #expect(attempt.rawNonce.isEmpty == false)
        #expect(attempt.hashedNonceForApple == AppleSignInNonce.sha256(attempt.rawNonce))
        #expect(attempt.hashedNonceForApple != attempt.rawNonce)
        #expect(attempt.rawNonceForFirebase == attempt.rawNonce)
        #expect(attempt.rawNonceForFirebase != attempt.hashedNonceForApple)
    }

    @Test("Firebase receives rawNonce not hashed nonce")
    func firebaseReceivesRawNonce() {
        let attempt = AppleSignInNonceAttempt(rawNonce: "once-per-attempt-raw")
        #expect(attempt.rawNonceForFirebase == "once-per-attempt-raw")
        #expect(attempt.hashedNonceForApple == AppleSignInNonce.sha256("once-per-attempt-raw"))
        #expect(attempt.rawNonceForFirebase != attempt.hashedNonceForApple)
    }

    @Test("Second Apple sign-in attempt receives a new nonce")
    func secondAttemptNewNonce() {
        let first = AppleSignInNonceAttempt.make()
        let second = AppleSignInNonceAttempt.make()
        #expect(first.rawNonce != second.rawNonce)
        #expect(first.hashedNonceForApple != second.hashedNonceForApple)
    }

    @Test("Missing identity token fails safely")
    func missingIdentityTokenFailsSafely() {
        #expect(AppleIdentityTokenPolicy.utf8String(from: nil) == nil)
        #expect(AppleIdentityTokenPolicy.utf8String(from: Data()) == nil)
        #expect(AppleIdentityTokenPolicy.utf8String(from: Data([0xFF, 0xFE])) == nil)
        let valid = AppleIdentityTokenPolicy.utf8String(from: Data("header.payload.sig".utf8))
        #expect(valid == "header.payload.sig")
        #expect(UserFacingError.message(for: CollaborationError.missingIdentityToken).isEmpty == false)
    }

    @Test("Auth failure outcome does not imply local project mutation")
    func authFailureLeavesLocalProjectsUntouched() {
        // Auth session flow only returns UI/auth outcomes; personal projects remain SwiftData-local.
        let outcome = AuthSessionFlowPolicy.outcome(
            authenticatedSession: nil,
            signInError: CollaborationError.invalidCredential,
            profileSyncFailed: false
        )
        #expect(outcome == .signedOutWithError)
        #expect(CollaborationArchitecturePolicy.sourceOfTruth(isShared: false) == "SwiftData")
        #expect(CollaborationArchitecturePolicy.personalProjectSourceOfTruth == "SwiftData")
    }

    @Test("Missing or invalid nonce maps to sign-in failure")
    func missingOrInvalidNonceMapping() {
        let nonceError = NSError(
            domain: FirebaseAuthErrorPolicy.errorDomain,
            code: FirebaseAuthErrorPolicy.missingOrInvalidNonceCode,
            userInfo: [FirebaseAuthErrorPolicy.errorNameKey: "ERROR_MISSING_OR_INVALID_NONCE"]
        )
        #expect(FirebaseAuthErrorPolicy.isMissingOrInvalidNonce(nonceError))
        #expect(FirebaseAuthErrorPolicy.collaborationError(for: nonceError) == .signInFailed)
        let info = FirebaseAuthErrorPolicy.debugInfo(for: nonceError)
        #expect(info.code == 17094)
        #expect(info.name == "ERROR_MISSING_OR_INVALID_NONCE")
        #expect(info.classification == .missingOrInvalidNonce)
    }

    @Test("Firebase error classification covers common auth failures")
    func firebaseErrorClassification() {
        let invalidCredential = NSError(
            domain: FirebaseAuthErrorPolicy.errorDomain,
            code: FirebaseAuthErrorPolicy.invalidCredentialCode,
            userInfo: [FirebaseAuthErrorPolicy.errorNameKey: "ERROR_INVALID_CREDENTIAL"]
        )
        #expect(FirebaseAuthErrorPolicy.classify(invalidCredential) == .invalidCredential)

        let operationNotAllowed = NSError(
            domain: FirebaseAuthErrorPolicy.errorDomain,
            code: FirebaseAuthErrorPolicy.operationNotAllowedCode
        )
        #expect(FirebaseAuthErrorPolicy.classify(operationNotAllowed) == .operationNotAllowed)

        let network = NSError(
            domain: FirebaseAuthErrorPolicy.errorDomain,
            code: FirebaseAuthErrorPolicy.networkErrorCode
        )
        #expect(FirebaseAuthErrorPolicy.classify(network) == .networkError)
    }

    @Test("Apple identity token claim report avoids logging token contents")
    func appleIdentityTokenClaimReport() {
        let header = Data("{}".utf8).base64EncodedString()
        let payloadJSON = """
        {"iss":"https://appleid.apple.com","aud":"com.anashamad.Todoshi","nonce":"hashed-nonce"}
        """
        let payload = Data(payloadJSON.utf8).base64EncodedString()
        let token = "\(header).\(payload).signature"

        let report = AppleIdentityTokenDiagnostics.report(for: token)
        #expect(report.identityTokenPresent == true)
        #expect(report.issuerIsApple == true)
        #expect(report.audienceMatchesExpected == true)
        #expect(report.nonceClaimPresent == true)
    }

    @Test("Runtime bundle identifier audit compares expected app ID")
    func runtimeBundleIdentifierAudit() {
        let match = AuthRuntimeIdentityAudit.report(bundleIdentifier: "com.anashamad.Todoshi")
        #expect(match.bundleIdentifierMatchesExpected == true)

        let mismatch = AuthRuntimeIdentityAudit.report(bundleIdentifier: "com.anashamad.todoshi")
        #expect(mismatch.bundleIdentifierMatchesExpected == false)
    }

    @Test("Firestore profile payload omits nil name/email and sets createdAt only on create")
    func firestoreProfilePayloadPolicy() {
        let first = FirestoreUserProfilePayloadPolicy.payload(
            existing: nil,
            incoming: FirebaseUserProfileFields(displayName: nil, email: nil),
            documentExists: false
        )
        #expect(first.includeCreatedAt == true)
        #expect(first.displayName == nil)
        #expect(first.email == nil)
        #expect(first.fieldKeys == Set(["createdAt", "updatedAt"]))

        let subsequent = FirestoreUserProfilePayloadPolicy.payload(
            existing: FirebaseUserProfileFields(displayName: "Anas", email: "keep@example.com"),
            incoming: FirebaseUserProfileFields(displayName: nil, email: nil),
            documentExists: true
        )
        #expect(subsequent.includeCreatedAt == false)
        #expect(subsequent.displayName == "Anas")
        #expect(subsequent.email == "keep@example.com")
        #expect(subsequent.fieldKeys == Set(["displayName", "email", "updatedAt"]))
    }

    @Test("Firestore error classification covers permission and availability failures")
    func firestoreErrorClassification() {
        let permission = NSError(
            domain: FirestoreErrorPolicy.errorDomain,
            code: FirestoreErrorPolicy.permissionDeniedCode
        )
        #expect(FirestoreErrorPolicy.classify(permission) == .permissionDenied)

        let unavailable = NSError(
            domain: FirestoreErrorPolicy.errorDomain,
            code: FirestoreErrorPolicy.unavailableCode
        )
        #expect(FirestoreErrorPolicy.classify(unavailable) == .unavailable)

        let failedPrecondition = NSError(
            domain: FirestoreErrorPolicy.errorDomain,
            code: FirestoreErrorPolicy.failedPreconditionCode
        )
        #expect(FirestoreErrorPolicy.classify(failedPrecondition) == .failedPrecondition)
    }

    @Test("Profile merge preserves existing non-nil values")
    func profileMergePreservesExisting() {
        let existing = FirebaseUserProfileFields(displayName: "Anas", email: "keep@example.com")
        let incoming = FirebaseUserProfileFields(displayName: nil, email: nil)
        let merged = FirebaseUserProfileMergePolicy.merged(existing: existing, incoming: incoming)
        #expect(merged.displayName == "Anas")
        #expect(merged.email == "keep@example.com")
    }

    @Test("Profile merge accepts incoming values when existing is empty")
    func profileMergeAcceptsIncoming() {
        let merged = FirebaseUserProfileMergePolicy.merged(
            existing: FirebaseUserProfileFields(displayName: nil, email: nil),
            incoming: FirebaseUserProfileFields(displayName: "Anas", email: "new@example.com")
        )
        #expect(merged.displayName == "Anas")
        #expect(merged.email == "new@example.com")
    }

    @Test("Profile merge allows missing displayName and email")
    func profileMergeAllowsMissingFields() {
        let merged = FirebaseUserProfileMergePolicy.merged(
            existing: nil,
            incoming: FirebaseUserProfileFields(displayName: nil, email: nil)
        )
        #expect(merged.displayName == nil)
        #expect(merged.email == nil)
    }

    @Test("Local-only backend remains safe when Firebase unavailable")
    func localOnlyWhenFirebaseUnavailable() async throws {
        let backend = LocalOnlyCollaborationBackend()
        #expect(backend.isConfigured == false)
        #expect(try await backend.currentSession() == nil)
        #expect(CollaborationConfigurationPolicy.status(isFirebaseConfigured: false) == .configuredLocalOnly)
    }

    @Test("Collaboration errors map to user-facing account messages")
    func collaborationErrorMessages() {
        #expect(UserFacingError.message(for: CollaborationError.signInCancelled).isEmpty == false)
        #expect(UserFacingError.message(for: CollaborationError.notConfigured).isEmpty == false)
        #expect(UserFacingError.message(for: CollaborationError.profileSyncFailed).isEmpty == false)
        #expect(UserFacingError.message(for: CollaborationError.signInFailed).isEmpty == false)
    }

    @Test("Profile sync failure maps to non-blocking warning copy")
    func profileSyncWarningCopy() {
        let message = UserFacingError.message(for: CollaborationError.profileSyncFailed)
        #expect(message.contains("signed in") || message.contains("تسجيل الدخول"))
    }

    @Test("Auth failure maps to sign-in error copy")
    func authFailureCopy() {
        let message = UserFacingError.message(for: CollaborationError.signInFailed)
        #expect(message.contains("sign in") || message.contains("تسجيل الدخول"))
    }

    @Test("Firebase Auth NSError maps to sign-in errors")
    func firebaseAuthErrorMapping() {
        let invalidCredential = NSError(
            domain: FirebaseAuthErrorPolicy.errorDomain,
            code: 17004
        )
        #expect(FirebaseAuthErrorPolicy.collaborationError(for: invalidCredential) == .invalidCredential)
        #expect(UserFacingError.message(for: invalidCredential).isEmpty == false)

        let genericFailure = NSError(
            domain: FirebaseAuthErrorPolicy.errorDomain,
            code: 17999
        )
        #expect(FirebaseAuthErrorPolicy.collaborationError(for: genericFailure) == .signInFailed)
    }

    @Test("Authenticated session survives profile sync failure")
    func authSurvivesProfileSyncFailure() {
        let session = CollaborationSession(
            user: CollaborationUser(id: "firebase-uid-123", displayName: nil, email: nil)
        )
        let outcome = AuthSessionFlowPolicy.outcome(
            authenticatedSession: session,
            signInError: CollaborationError.profileSyncFailed,
            profileSyncFailed: true
        )
        #expect(outcome == .signedIn(profileSyncWarning: true))
    }

    @Test("Profile failure cannot sign user out when auth session exists")
    func profileFailureDoesNotSignOut() {
        let session = CollaborationSession(
            user: CollaborationUser(id: "firebase-uid-123", displayName: "Anas", email: nil)
        )
        let outcome = AuthSessionFlowPolicy.outcome(
            authenticatedSession: session,
            signInError: nil,
            profileSyncFailed: true
        )
        if case .signedIn(let warning) = outcome {
            #expect(warning == true)
        } else {
            Issue.record("Expected signed-in outcome")
        }
    }

    @Test("Restored session does not depend on profile write success")
    func restoredSessionIndependentOfProfileWrite() {
        let session = CollaborationSession(
            user: CollaborationUser(id: "firebase-uid-restored", displayName: "Anas", email: "a@example.com")
        )
        let outcome = AuthSessionFlowPolicy.outcome(
            authenticatedSession: session,
            signInError: nil,
            profileSyncFailed: false
        )
        #expect(outcome == .signedIn(profileSyncWarning: false))
    }

    @Test("Auth failure without session remains signed out")
    func authFailureWithoutSession() {
        let outcome = AuthSessionFlowPolicy.outcome(
            authenticatedSession: nil,
            signInError: CollaborationError.signInFailed,
            profileSyncFailed: false
        )
        #expect(outcome == .signedOutWithError)
    }
}

private extension Character {
    var isHexDigit: Bool {
        ("0"..."9").contains(self) || ("a"..."f").contains(self)
    }
}
