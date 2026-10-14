import Foundation
import Testing
@testable import TodoshiCore

@Suite("User Profile Phase 1.1")
struct PhaseUserProfileTests {
    @Test("Display name validation trims and rejects blank names")
    func displayNameValidation() {
        #expect(ProfileDisplayNameValidation.validated("  Anas  ") == .success("Anas"))
        #expect(ProfileDisplayNameValidation.validated("   ") == .failure(.empty))
        #expect(ProfileDisplayNameValidation.validated("") == .failure(.empty))
        let long = String(repeating: "a", count: 61)
        #expect(ProfileDisplayNameValidation.validated(long) == .failure(.tooLong))
        #expect(ProfileDisplayNameValidation.validated(String(repeating: "b", count: 60)) == .success(String(repeating: "b", count: 60)))
    }

    @Test("Email duplicate display is suppressed")
    func emailDuplicateSuppression() {
        let duplicate = ProfileIdentityPresentation.lines(
            displayName: "user@example.com",
            email: "user@example.com",
            fallback: "Account"
        )
        #expect(duplicate.primary == "user@example.com")
        #expect(duplicate.secondary == nil)

        let distinct = ProfileIdentityPresentation.lines(
            displayName: "Anas",
            email: "user@example.com",
            fallback: "Account"
        )
        #expect(distinct.primary == "Anas")
        #expect(distinct.secondary == "user@example.com")

        let missingName = ProfileIdentityPresentation.lines(
            displayName: nil,
            email: "user@example.com",
            fallback: "Account"
        )
        #expect(missingName.primary == "Account")
        #expect(missingName.secondary == "user@example.com")
    }

    @Test("Two-word English name yields two initials")
    func englishTwoWordInitials() {
        #expect(ProfileAvatarInitialsPolicy.initials(from: "Anas Hamad") == "AH")
        #expect(ProfileAvatarInitialsPolicy.shouldShowPersonIcon(for: "Anas Hamad") == false)
    }

    @Test("One-word name yields one initial")
    func englishOneWordInitials() {
        #expect(ProfileAvatarInitialsPolicy.initials(from: "Anas") == "A")
    }

    @Test("Arabic name yields spaced initials and skips definite article")
    func arabicInitials() {
        #expect(ProfileAvatarInitialsPolicy.initials(from: "أنس الحميد") == "أ ح")
        #expect(ProfileAvatarInitialsPolicy.initials(from: "  أنس   الحميد  ") == "أ ح")
    }

    @Test("Whitespace-only name falls back to person icon policy")
    func missingNameFallback() {
        #expect(ProfileAvatarInitialsPolicy.initials(from: "  ") == "")
        #expect(ProfileAvatarInitialsPolicy.initials(from: nil) == "")
        #expect(ProfileAvatarInitialsPolicy.shouldShowPersonIcon(for: nil) == true)
        #expect(ProfileAvatarInitialsPolicy.shouldShowPersonIcon(for: "   ") == true)
    }

    @Test("Avatar path helpers remain valid for future Storage phase")
    func avatarPathForwardCompatibility() {
        let path = ProfileAvatarPathPolicy.path(forUserID: "uid-123")
        #expect(path == "profile-images/uid-123/avatar.jpg")
        #expect(ProfileAvatarPathPolicy.isValid(path!, forUserID: "uid-123"))
        #expect(ProfileAvatarPathPolicy.userID(from: path!) == "uid-123")
    }

    @Test("Profile merge preserves existing optional avatarPath without requiring Storage")
    func profileMergePreservesAvatarPathOptionally() {
        let existing = FirebaseUserProfileFields(
            displayName: "Anas",
            email: "keep@example.com",
            avatarPath: "profile-images/uid/avatar.jpg"
        )
        let incoming = FirebaseUserProfileFields(displayName: nil, email: nil, avatarPath: nil)
        let merged = FirebaseUserProfileMergePolicy.merged(existing: existing, incoming: incoming)
        #expect(merged.displayName == "Anas")
        #expect(merged.email == "keep@example.com")
        #expect(merged.avatarPath == "profile-images/uid/avatar.jpg")
    }

    @Test("MVP profile payload does not write avatarPath")
    func mvpPayloadOmitsAvatarPath() {
        let payload = FirestoreUserProfilePayloadPolicy.payload(
            existing: FirebaseUserProfileFields(
                displayName: "Anas",
                email: "a@example.com",
                avatarPath: "profile-images/uid/avatar.jpg"
            ),
            incoming: FirebaseUserProfileFields(displayName: "Anas Hamad", email: "a@example.com"),
            documentExists: true
        )
        #expect(payload.displayName == "Anas")
        #expect(payload.fieldKeys.contains("avatarPath") == false)
        #expect(payload.fieldKeys == Set(["displayName", "email", "updatedAt"]))
    }

    @Test("Signed-out profile access requires authentication")
    func signedOutProfileAccess() {
        #expect(CollaborationAuthGate.requirement(for: nil) == .requiresAuthentication)
    }

    @Test("Local Todoshi remains independent of Storage")
    func localUsageIndependentOfStorage() {
        #expect(CollaborationArchitecturePolicy.personalProjectSourceOfTruth == "SwiftData")
        #expect(CollaborationConfigurationPolicy.localOnlyGuarantee == true)
        let outcome = AuthSessionFlowPolicy.outcome(
            authenticatedSession: CollaborationSession(
                user: CollaborationUser(id: "uid", displayName: "Anas", email: nil)
            ),
            signInError: CollaborationError.profileUpdateFailed,
            profileSyncFailed: true
        )
        #expect(outcome == .signedIn(profileSyncWarning: true))
    }

    @Test("Profile display-name edit validation maps to user-facing errors")
    func profileEditErrorCopy() {
        #expect(UserFacingError.message(for: CollaborationError.profileNameInvalid).isEmpty == false)
        #expect(UserFacingError.message(for: CollaborationError.profileNameTooLong).isEmpty == false)
        #expect(UserFacingError.message(for: CollaborationError.profileUpdateFailed).isEmpty == false)
    }
}
