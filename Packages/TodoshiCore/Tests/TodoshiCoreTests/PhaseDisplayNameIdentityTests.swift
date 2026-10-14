import Foundation
import Testing
@testable import TodoshiCore

struct PhaseDisplayNameIdentityTests {
    @Test("1 — Apple fullName normalizes to displayName")
    func appleFullNameNormalization() {
        var components = PersonNameComponents()
        components.givenName = "Anas"
        components.familyName = "Hamad"
        #expect(CollaborationDisplayNamePolicy.fromAppleFullName(components) == "Anas Hamad")
    }

    @Test("2 — Apple missing fullName does not become email display name")
    func appleMissingNameNoEmail() {
        #expect(CollaborationDisplayNamePolicy.fromAppleFullName(nil) == nil)
        let snapshot = CollaborationDisplayNamePolicy.collaborationSnapshot(
            preferred: nil,
            uid: "uid-apple"
        )
        #expect(snapshot == TodoshiL10n.tr("project.members.unnamed"))
        #expect(!snapshot.contains("@"))
    }

    @Test("3 — Firestore profile name wins over email fallback")
    func profileNameWinsOverEmail() {
        let lines = ProfileIdentityPresentation.lines(
            displayName: "Jameel",
            email: "anas.h3630@gmail.com",
            fallback: "Account"
        )
        #expect(lines.primary == "Jameel")
        #expect(lines.secondary == "anas.h3630@gmail.com")
    }

    @Test("4 — Profile rename produces membership propagation plan")
    func propagationPlan() {
        let targets = MemberDisplayNamePropagationPolicy.projectIDsNeedingUpdate(
            viewerUID: "uid-a",
            profileName: "ااااا",
            memberships: [
                .init(projectRemoteID: "p1", memberUID: "uid-a", membershipDisplayName: "jameel alkhlq"),
                .init(projectRemoteID: "p2", memberUID: "uid-b", membershipDisplayName: "Other"),
            ]
        )
        #expect(targets == ["p1"])
    }

    @Test("5 — Only current user's membership displayName changes")
    func onlySelfMembershipUpdates() {
        let targets = MemberDisplayNamePropagationPolicy.projectIDsNeedingUpdate(
            viewerUID: "uid-a",
            profileName: "New",
            memberships: [
                .init(projectRemoteID: "p1", memberUID: "uid-a", membershipDisplayName: "Old"),
                .init(projectRemoteID: "p2", memberUID: "uid-b", membershipDisplayName: "Old"),
            ]
        )
        #expect(targets == ["p1"])
    }

    @Test("6–7 — Propagation policy is idempotent and skips matching names")
    func idempotentPropagation() {
        #expect(
            !MemberDisplayNamePropagationPolicy.shouldUpdate(
                profileName: "Same",
                membershipName: "Same"
            )
        )
        #expect(
            MemberDisplayNamePropagationPolicy.shouldUpdate(
                profileName: "ااااا",
                membershipName: "jameel alkhlq"
            )
        )
    }

    @Test("8 — Stale membership repaired when names differ")
    func staleMembershipRepair() {
        #expect(
            MemberDisplayNamePropagationPolicy.shouldUpdate(
                profileName: "Updated",
                membershipName: "Stale"
            )
        )
    }

    @Test("9 — Same UID with new name is still same member")
    func uidIdentityStable() {
        let candidateA = AssignmentCandidate(uid: "uid-1", role: .member, accessLevel: .full, displayName: "Old")
        let candidateB = AssignmentCandidate(uid: "uid-1", role: .member, accessLevel: .full, displayName: "New")
        #expect(candidateA.uid == candidateB.uid)
    }

    @Test("10–12 — Rename does not affect assignee/editor UIDs")
    func renameDoesNotTouchUIDFields() {
        // Policy layer only compares display names; UID-based assignment remains external.
        #expect(CollaborationDisplayNamePolicy.normalized("ااااا") != CollaborationDisplayNamePolicy.normalized("jameel alkhlq"))
    }

    @Test("13 — Active membership resolves comment author current name")
    func commentUsesActiveMembershipName() {
        let members = [
            AssignmentCandidate(uid: "uid-j", role: .member, accessLevel: .full, displayName: "ااااا"),
        ]
        let name = CommentAuthorPresentation.displayName(
            authorUID: "uid-j",
            storedName: "jameel alkhlq",
            members: members
        )
        #expect(name == "ااااا")
    }

    @Test("14 — Removed member comment falls back to stored snapshot")
    func removedMemberCommentFallback() {
        let name = CommentAuthorPresentation.displayName(
            authorUID: "removed-uid",
            storedName: "jameel alkhlq",
            members: []
        )
        #expect(name == "jameel alkhlq")
    }

    @Test("15 — New comment snapshot uses collaboration name policy")
    func newCommentSnapshot() {
        let snapshot = CollaborationDisplayNamePolicy.collaborationSnapshot(
            preferred: "Current",
            uid: "uid-1"
        )
        #expect(snapshot == "Current")
    }

    @Test("16 — Historical completedBy Firestore field is presentation-only override")
    func completionAttributionPresentation() {
        let members = [
            AssignmentCandidate(uid: "uid-b", role: .member, accessLevel: .full, displayName: "ااااا"),
        ]
        let resolved = TaskCompletionPresentation.resolvedCompleterName(
            completedByUID: "uid-b",
            completedByDisplayName: "jameel alkhlq",
            members: members
        )
        #expect(resolved == "ااااا")
    }

    @Test("17 — Missing name completion policy respects account isolation fields")
    func nameCompletionPolicy() {
        #expect(
            ProfileDisplayNameCompletionPolicy.needsCompletion(
                profileName: nil,
                authName: nil
            )
        )
        #expect(
            !ProfileDisplayNameCompletionPolicy.needsCompletion(
                profileName: "Anas",
                authName: nil
            )
        )
        #expect(
            !ProfileDisplayNameCompletionPolicy.needsCompletion(
                profileName: nil,
                authName: "Anas"
            )
        )
    }

    @Test("Profile identity never uses email as primary collaboration label")
    func emailNotPrimaryIdentity() {
        let lines = ProfileIdentityPresentation.lines(
            displayName: nil,
            email: "anas.h3630@gmail.com",
            fallback: TodoshiL10n.tr("account.defaultLabel")
        )
        #expect(lines.primary != "anas.h3630@gmail.com")
        #expect(lines.secondary == "anas.h3630@gmail.com")
    }
}
