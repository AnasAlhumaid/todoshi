import Foundation
import Testing
@testable import TodoshiCore

struct PhaseMemberProfilePresentationTests {
    @Test("1 — Owner profile shows displayName")
    func ownerProfileShowsDisplayName() {
        #expect(
            MemberProfilePresentationPolicy.displayName(from: "Anas Hamad") == "Anas Hamad"
        )
    }

    @Test("2 — Owner profile shows Todoshi ID policy for managed member")
    func ownerProfileShowsTodoshiID() {
        #expect(
            MemberProfilePresentationPolicy.showsTodoshiID(
                isOwnerViewer: true,
                memberRole: .member
            )
        )
    }

    @Test("3 — Rename updates displayName but ID policy unchanged")
    func renameUpdatesDisplayNamePreservesIDPolicy() {
        let before = MemberProfilePresentationPolicy.displayName(from: "Jameel Alkhlq")
        let after = MemberProfilePresentationPolicy.displayName(from: "ااااا")
        #expect(before == "Jameel Alkhlq")
        #expect(after == "ااااا")
        #expect(
            MemberProfilePresentationPolicy.showsTodoshiID(
                isOwnerViewer: true,
                memberRole: .member
            )
        )
    }

    @Test("4 — Email never used as member profile name")
    func emailNeverUsedAsName() {
        #expect(
            MemberProfilePresentationPolicy.usesMembershipDisplayName(
                membershipName: nil,
                email: "relay@privaterelay.appleid.com"
            ) == TodoshiL10n.tr("project.members.unnamed")
        )
        #expect(
            !MemberProfilePresentationPolicy.displayName(from: "Anas").contains("@")
        )
    }

    @Test("5 — Firebase UID not exposed in accessibility label")
    func firebaseUIDNotExposed() {
        let label = MemberProfilePresentationPolicy.accessibilityLabel(
            displayName: "Anas",
            role: .member,
            todoshiId: "TD-7K4P-9Q2M-X5R7Q"
        )
        #expect(!label.contains("firebase"))
        #expect(!label.contains("uid-"))
    }

    @Test("6 — Full access presentation")
    func fullAccessPresentation() {
        #expect(
            MemberProfilePresentationPolicy.accessSummary(
                role: .member,
                accessLevel: .full
            ) == SharedTaskPermissionPresentation.fullAccess
        )
    }

    @Test("7 — Restricted presentation")
    func restrictedPresentation() {
        #expect(
            MemberProfilePresentationPolicy.accessSummary(
                role: .member,
                accessLevel: .restricted
            ) == SharedTaskPermissionPresentation.selectedTasksOnly
        )
    }

    @Test("8 — Tasks member progress terminology")
    func tasksProgressTerminology() {
        #expect(
            ProjectTerminologyPolicy.assignedSection(.tasks)
                == TodoshiL10n.tr("task.assignment.assignedTasks")
        )
        #expect(
            ProjectStatusPolicy.progressStatuses(for: .tasks).contains(.inProgress)
        )
        #expect(
            ProjectStatusPolicy.progressStatuses(for: .tasks).contains(.review)
        )
    }

    @Test("9 — Checklist member progress terminology")
    func checklistProgressTerminology() {
        #expect(
            ProjectTerminologyPolicy.assignedSection(.checklist)
                == TodoshiL10n.tr("project.checklist.assignedItems")
        )
        let statuses = ProjectStatusPolicy.progressStatuses(for: .checklist)
        #expect(statuses == [.todo, .inProgress, .done])
        #expect(!statuses.contains(.review))
        #expect(!statuses.contains(.backlog))
    }

    @Test("10 — Normal member does not receive owner controls")
    func normalMemberNoOwnerControls() {
        #expect(
            !MemberProfilePresentationPolicy.showsOwnerManagementControls(
                isOwnerViewer: false,
                memberRole: .member
            )
        )
        #expect(
            !MemberProfilePresentationPolicy.showsTodoshiID(
                isOwnerViewer: false,
                memberRole: .member
            )
        )
    }

    @Test("11 — Missing public identity does not expose fallback UID/email")
    func missingIdentityNoFallback() {
        let label = MemberProfilePresentationPolicy.accessibilityLabel(
            displayName: "Anas",
            role: .member,
            todoshiId: nil
        )
        #expect(!label.contains("@"))
        #expect(!label.contains("uid"))
    }
}
