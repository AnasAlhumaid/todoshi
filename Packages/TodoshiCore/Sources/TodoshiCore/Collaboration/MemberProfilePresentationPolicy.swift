import Foundation

/// Owner Member Profile presentation — membership snapshot + public identity only.
public enum MemberProfilePresentationPolicy: Sendable {
    public static var screenTitle: String { TodoshiL10n.tr("project.members.profile.title") }
    public static var permissionsSummaryTitle: String { TodoshiL10n.tr("project.members.profile.permissions") }

    public static func displayName(from membershipName: String?) -> String {
        TaskAssignmentPresentation.memberDisplayName(membershipName)
    }

    public static func accessSummary(
        role: ProjectMemberRole,
        accessLevel: ProjectMemberAccessLevel
    ) -> String {
        if role == .owner {
            return SharedTaskPermissionPresentation.alwaysOwner
        }
        return accessLevel == .full
            ? SharedTaskPermissionPresentation.fullAccess
            : SharedTaskPermissionPresentation.selectedTasksOnly
    }

    public static func showsOwnerManagementControls(
        isOwnerViewer: Bool,
        memberRole: ProjectMemberRole
    ) -> Bool {
        isOwnerViewer && memberRole != .owner
    }

    public static func showsTodoshiID(
        isOwnerViewer: Bool,
        memberRole: ProjectMemberRole
    ) -> Bool {
        TodoshiIdentityPresentationPolicy.showsMemberTodoshiID(
            isOwnerManagingMember: isOwnerViewer && memberRole != .owner
        )
    }

    public static func showsWorkSummary(
        isOwnerViewer: Bool,
        memberUID: String,
        viewerUID: String?
    ) -> Bool {
        isOwnerViewer || memberUID == viewerUID
    }

    public static func showsAccessSummary(
        isOwnerViewer: Bool,
        memberUID: String,
        viewerUID: String?
    ) -> Bool {
        isOwnerViewer || memberUID == viewerUID
    }

    public static func accessibilityLabel(
        displayName: String,
        role: ProjectMemberRole,
        todoshiId: String?
    ) -> String {
        var parts = [displayName, SharedProjectPresentation.memberRoleLabel(role)]
        if let todoshiId {
            parts.append(
                "\(TodoshiL10n.tr("identity.todoshiId.label")) \(TodoshiIDPolicy.accessibilitySpoken(todoshiId))"
            )
        }
        return parts.joined(separator: ", ")
    }

    /// Membership displayName is never substituted with email.
    public static func usesMembershipDisplayName(
        membershipName: String?,
        email: String?
    ) -> String {
        let resolved = displayName(from: membershipName)
        guard let email, !email.isEmpty else { return resolved }
        return resolved == email || resolved.contains("@")
            ? TodoshiL10n.tr("project.members.unnamed")
            : resolved
    }
}
