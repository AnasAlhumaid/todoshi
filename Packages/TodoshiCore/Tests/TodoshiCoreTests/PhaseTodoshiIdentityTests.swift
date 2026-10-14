import Foundation
import Testing
@testable import TodoshiCore

struct PhaseTodoshiIdentityTests {
    private let sampleBytes: [UInt8] = [
        0x7A, 0x4B, 0x9C, 0x2E, 0xF1, 0x08, 0xD3, 0x65,
    ]

    @Test("1 — generated ID format is valid")
    func validFormat() {
        let id = TodoshiIDPolicy.generate(randomBytes: sampleBytes)
        #expect(TodoshiIDPolicy.isValid(id))
    }

    @Test("2 — prefix is TD-")
    func prefix() {
        let id = TodoshiIDPolicy.generate(randomBytes: sampleBytes)
        #expect(TodoshiIDPolicy.hasValidPrefix(id))
    }

    @Test("3 — payload uses allowed alphabet")
    func allowedAlphabet() {
        let id = TodoshiIDPolicy.generate(randomBytes: sampleBytes)
        #expect(TodoshiIDPolicy.usesAllowedAlphabet(id))
    }

    @Test("4 — payload has adequate length")
    func adequateLength() {
        let id = TodoshiIDPolicy.generate(randomBytes: sampleBytes)
        let payload = id.replacingOccurrences(of: "TD-", with: "").replacingOccurrences(of: "-", with: "")
        #expect(payload.count == TodoshiIDPolicy.payloadCharacterCount)
    }

    @Test("5 — existing ID is never regenerated")
    func existingNeverRegenerated() {
        let existing = "TD-7K4P-9Q2M-X5R7Q"
        let decision = TodoshiIdentityProvisioningPolicy.decide(
            existingUserTodoshiId: existing,
            candidate: TodoshiIDPolicy.generate(randomBytes: sampleBytes),
            claimExists: false,
            claimUID: nil,
            actingUID: "uid-a"
        )
        #expect(decision == .useExisting(existing))
    }

    @Test("6 — profile rename preserves ID via merge policy")
    func profileRenamePreservesID() {
        let merged = FirebaseUserProfileMergePolicy.merged(
            existing: FirebaseUserProfileFields(
                displayName: "Jameel",
                todoshiId: "TD-7K4P-9Q2M-X5R7Q"
            ),
            incoming: FirebaseUserProfileFields(
                displayName: "ااااا",
                todoshiId: "TD-AAAA-BBBB-CCCCC"
            )
        )
        #expect(merged.todoshiId == "TD-7K4P-9Q2M-X5R7Q")
    }

    @Test("7 — email change preserves ID")
    func emailChangePreservesID() {
        let merged = FirebaseUserProfileMergePolicy.merged(
            existing: FirebaseUserProfileFields(
                displayName: "Anas",
                email: "old@example.com",
                todoshiId: "TD-7K4P-9Q2M-X5R7Q"
            ),
            incoming: FirebaseUserProfileFields(displayName: "Anas", email: "new@example.com")
        )
        #expect(merged.email == "old@example.com")
        #expect(merged.todoshiId == "TD-7K4P-9Q2M-X5R7Q")
    }

    @Test("8 — same UID resolves same ID")
    func sameUIDSameID() {
        let resolved = TodoshiIdentityProvisioningPolicy.resolvedIdentity(
            existingUserTodoshiId: "TD-7K4P-9Q2M-X5R7Q",
            publicIdentityTodoshiId: "TD-AAAA-BBBB-CCCCC"
        )
        #expect(resolved == "TD-7K4P-9Q2M-X5R7Q")
    }

    @Test("9 — different UID cannot claim existing ID")
    func differentUIDCannotClaim() {
        let decision = TodoshiIdentityProvisioningPolicy.decide(
            existingUserTodoshiId: nil,
            candidate: "TD-7K4P-9Q2M-X5R7Q",
            claimExists: true,
            claimUID: "other-uid",
            actingUID: "uid-a"
        )
        #expect(decision == .retryCollision)
    }

    @Test("10 — collision triggers candidate retry")
    func collisionRetry() {
        let decision = TodoshiIdentityProvisioningPolicy.decide(
            existingUserTodoshiId: nil,
            candidate: "TD-7K4P-9Q2M-X5R7Q",
            claimExists: true,
            claimUID: "someone-else",
            actingUID: "uid-a"
        )
        #expect(decision == .retryCollision)
    }

    @Test("11 — concurrent provisioning respects existing user ID")
    func concurrentProvisioningUsesExisting() {
        let existing = "TD-7K4P-9Q2M-X5R7Q"
        let decision = TodoshiIdentityProvisioningPolicy.decide(
            existingUserTodoshiId: existing,
            candidate: "TD-AAAA-BBBB-CCCCC",
            claimExists: true,
            claimUID: "uid-a",
            actingUID: "uid-a"
        )
        #expect(decision == .useExisting(existing))
    }

    @Test("12 — public identity maps UID to same ID")
    func publicIdentityMapping() {
        let identity = TodoshiPublicIdentity(userID: "uid-a", todoshiId: "TD-7K4P-9Q2M-X5R7Q")
        #expect(identity.userID == "uid-a")
        #expect(identity.todoshiId == "TD-7K4P-9Q2M-X5R7Q")
    }

    @Test("13 — owner presentation shows ID")
    func ownerPresentationShowsID() {
        #expect(TodoshiIdentityPresentationPolicy.showsMemberTodoshiID(isOwnerManagingMember: true))
    }

    @Test("14 — normal member presentation hides ID")
    func memberPresentationHidesID() {
        #expect(!TodoshiIdentityPresentationPolicy.showsMemberTodoshiID(isOwnerManagingMember: false))
    }

    @Test("15 — personal profile shows own ID")
    func profileShowsOwnID() {
        #expect(TodoshiIdentityPresentationPolicy.showsOwnTodoshiIDInProfile(isSignedIn: true))
    }

    @Test("16 — member removal does not release global ID")
    func memberRemovalKeepsGlobalID() {
        #expect(TodoshiIdentityProvisioningPolicy.shouldProvision(existingTodoshiId: "TD-7K4P-9Q2M-X5R7Q") == false)
    }

    @Test("17 — Apple relay email has no effect on ID")
    func relayEmailNoEffect() {
        let merged = FirebaseUserProfileMergePolicy.merged(
            existing: FirebaseUserProfileFields(
                displayName: "Jameel",
                email: "abcd@privaterelay.appleid.com",
                todoshiId: "TD-7K4P-9Q2M-X5R7Q"
            ),
            incoming: FirebaseUserProfileFields(
                displayName: "Jameel",
                email: "efgh@privaterelay.appleid.com"
            )
        )
        #expect(merged.todoshiId == "TD-7K4P-9Q2M-X5R7Q")
    }

    @Test("18 — missing ID should be provisioned on session restore")
    func missingIDShouldProvision() {
        #expect(TodoshiIdentityProvisioningPolicy.shouldProvision(existingTodoshiId: nil))
        #expect(TodoshiIdentityProvisioningPolicy.shouldProvision(existingTodoshiId: ""))
        #expect(TodoshiIdentityProvisioningPolicy.shouldProvision(existingTodoshiId: "not-a-valid-id"))
    }

    @Test("19 — null legacy todoshiId is treated as unprovisioned")
    func nullLegacyTodoshiIdUnprovisioned() {
        #expect(TodoshiIdentityProvisioningPolicy.shouldProvision(existingTodoshiId: nil))
        #expect(TodoshiIdentityProvisioningPolicy.normalized(nil) == nil)
    }

    @Test("20 — session policy merges ID into stale profile")
    func sessionMergesStaleProfile() {
        let profile = CollaborationProfile(userID: "uid-a", displayName: "Anas", email: "a@example.com")
        let merged = TodoshiIdentitySessionPolicy.mergedProfile(profile, todoshiId: "TD-7K4P-9Q2M-X5R7Q")
        #expect(merged.todoshiId == "TD-7K4P-9Q2M-X5R7Q")
        #expect(merged.displayName == "Anas")
    }

    @Test("21 — already-provisioned session restores ID for presentation")
    func sessionRestoresProvisionedID() {
        let resolved = TodoshiIdentitySessionPolicy.resolvedTodoshiId(
            profileTodoshiId: nil,
            sessionTodoshiId: "TD-7K4P-9Q2M-X5R7Q"
        )
        #expect(resolved == "TD-7K4P-9Q2M-X5R7Q")
    }

    @Test("22 — provisioning success should refresh stale nil profile")
    func shouldRefreshStaleProfile() {
        #expect(
            TodoshiIdentitySessionPolicy.shouldReloadProfile(
                profileTodoshiId: nil,
                sessionTodoshiId: "TD-7K4P-9Q2M-X5R7Q"
            )
        )
    }

    @Test("23 — profile presentation resolves session ID after provisioning")
    func profilePresentationUsesSessionFallback() {
        let profile = CollaborationProfile(userID: "uid-a", displayName: "Anas")
        let resolved = TodoshiIdentitySessionPolicy.resolvedTodoshiId(
            profileTodoshiId: profile.todoshiId,
            sessionTodoshiId: "TD-7K4P-9Q2M-X5R7Q"
        )
        #expect(resolved == "TD-7K4P-9Q2M-X5R7Q")
    }

    @Test("24 — provisioning warning clears once session has ID")
    func warningClearsWithSessionID() {
        #expect(
            TodoshiIdentitySessionPolicy.shouldClearProvisioningWarning(
                sessionTodoshiId: "TD-7K4P-9Q2M-X5R7Q"
            )
        )
        #expect(
            !TodoshiIdentitySessionPolicy.shouldClearProvisioningWarning(sessionTodoshiId: nil)
        )
    }

    @Test("25 — existing profile without todoshiId still requires provisioning")
    func existingProfileRequiresProvisioning() {
        #expect(
            TodoshiIdentityProvisioningPolicy.shouldProvision(
                existingTodoshiId: nil
            )
        )
        #expect(
            TodoshiIdentitySessionPolicy.shouldRunProvisioning(
                cachedSessionTodoshiId: nil,
                canonicalTodoshiId: nil
            )
        )
    }

    @Test("26 — existing profile must not early-return provisioning when ID missing")
    func existingProfileDoesNotSkipProvisioning() {
        #expect(
            !TodoshiIdentitySessionPolicy.shouldSkipProvisioning(
                cachedSessionTodoshiId: nil,
                canonicalTodoshiId: nil
            )
        )
        #expect(
            TodoshiIdentitySessionPolicy.shouldSkipProvisioning(
                cachedSessionTodoshiId: "TD-7K4P-9Q2M-X5R7Q",
                canonicalTodoshiId: nil
            )
        )
    }

    @Test("27 — session restore is idempotent once canonical ID exists")
    func sessionRestoreIdempotent() {
        #expect(
            TodoshiIdentitySessionPolicy.shouldSkipProvisioning(
                cachedSessionTodoshiId: nil,
                canonicalTodoshiId: "TD-7K4P-9Q2M-X5R7Q"
            )
        )
    }

    @Test("28 — profile sync merge preserves todoshiId")
    func profileSyncPreservesTodoshiId() {
        let merged = FirebaseUserProfileMergePolicy.merged(
            existing: FirebaseUserProfileFields(
                displayName: "Anas",
                email: "a@example.com",
                todoshiId: "TD-7K4P-9Q2M-X5R7Q"
            ),
            incoming: FirebaseUserProfileFields(displayName: "New Name", email: "b@example.com")
        )
        #expect(merged.todoshiId == "TD-7K4P-9Q2M-X5R7Q")
    }

    @Test("29 — failed coalesced task should allow retry when session still missing ID")
    func coalescedFailureAllowsRetry() {
        #expect(
            TodoshiIdentitySessionPolicy.shouldRetryProvisioningAfterTask(
                cachedSessionTodoshiId: nil
            )
        )
        #expect(
            !TodoshiIdentitySessionPolicy.shouldRetryProvisioningAfterTask(
                cachedSessionTodoshiId: "TD-7K4P-9Q2M-X5R7Q"
            )
        )
    }
}
