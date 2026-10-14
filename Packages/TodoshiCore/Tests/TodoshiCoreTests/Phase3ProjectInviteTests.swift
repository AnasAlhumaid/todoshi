import Foundation
import Testing
@testable import TodoshiCore

struct Phase3ProjectInviteTests {
    @Test("Secure invite token is URL-safe Base64 ~43 chars with 256-bit entropy")
    func secureTokenFormat() {
        let token = ProjectInviteTokenGenerator.generate()
        #expect(ProjectInviteTokenGenerator.isValidFormat(token))
        #expect(token.count >= 40)
        #expect(token.count <= 64)
        #expect(!token.contains("+"))
        #expect(!token.contains("/"))
        #expect(!token.contains("="))
        #expect(ProjectInviteTokenGenerator.byteCount == 32)

        var seen = Set<String>()
        for _ in 0..<20 {
            seen.insert(ProjectInviteTokenGenerator.generate())
        }
        #expect(seen.count == 20)
    }

    @Test("Invite URL builder uses todoshi://invite/<token>")
    func inviteURLGeneration() {
        let token = ProjectInviteTokenGenerator.generate()
        let url = ProjectInviteURLBuilder.url(token: token)
        #expect(url?.scheme == "todoshi")
        #expect(url?.host == "invite")
        #expect(url?.path == "/\(token)")
        #expect(url?.absoluteString == "todoshi://invite/\(token)")
        #expect(ProjectInviteURLBuilder.url(token: "short") == nil)
        #expect(ProjectInviteURLBuilder.url(token: "nexus-not-allowed!!!") == nil)
    }

    @Test("Deep link parses valid invite and rejects malformed")
    func inviteDeepLinkParsing() {
        let token = ProjectInviteTokenGenerator.generate()
        let link = TodoshiDeepLink.invite(token: token)
        #expect(TodoshiDeepLink(url: link.url) == .invite(token: token))
        #expect(TodoshiDeepLink(url: URL(string: "todoshi://invite/\(token)")!) == .invite(token: token))

        #expect(TodoshiDeepLink(url: URL(string: "todoshi://invite/")!) == nil)
        #expect(TodoshiDeepLink(url: URL(string: "todoshi://invite/abc")!) == nil)
        #expect(TodoshiDeepLink(url: URL(string: "todoshi://invite/not+valid/token==")!) == nil)
        // Legacy nexus invite links are not accepted.
        #expect(TodoshiDeepLink(url: URL(string: "nexus://invite/\(token)")!) == nil)
    }

    @Test("Invite status presentation for expired/accepted/revoked/invalid")
    func inviteStatusPresentation() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(
            ProjectInviteStatusPolicy.status(
                acceptedBy: nil,
                revokedAt: nil,
                expiresAt: now.addingTimeInterval(3600),
                now: now
            ) == .valid
        )
        #expect(
            ProjectInviteStatusPolicy.status(
                acceptedBy: nil,
                revokedAt: nil,
                expiresAt: now.addingTimeInterval(-1),
                now: now
            ) == .expired
        )
        #expect(
            ProjectInviteStatusPolicy.status(
                acceptedBy: "uid",
                revokedAt: nil,
                expiresAt: now.addingTimeInterval(3600),
                now: now
            ) == .accepted
        )
        #expect(
            ProjectInviteStatusPolicy.status(
                acceptedBy: nil,
                revokedAt: now,
                expiresAt: now.addingTimeInterval(3600),
                now: now
            ) == .revoked
        )
        #expect(
            ProjectInviteStatusPolicy.status(
                acceptedBy: nil,
                revokedAt: nil,
                expiresAt: nil,
                now: now
            ) == .invalid
        )

        #expect(ProjectInviteStatusPolicy.userMessage(for: .expired).isEmpty == false)
        #expect(ProjectInviteStatusPolicy.userMessage(for: .accepted).isEmpty == false)
        #expect(ProjectInviteStatusPolicy.userMessage(for: .revoked).isEmpty == false)
        #expect(ProjectInviteStatusPolicy.userMessage(for: .invalid).isEmpty == false)
    }

    @Test("Role mapping: only owners can invite; member/owner labels")
    func roleMappingAndInvitePresentation() {
        #expect(ProjectInvitePresentation.canInviteMembers(role: .owner))
        #expect(!ProjectInvitePresentation.canInviteMembers(role: .member))
        #expect(!ProjectInvitePresentation.canInviteMembers(role: nil))
        #expect(SharedProjectPresentation.memberRoleLabel(.owner, locale: Locale(identifier: "en")).isEmpty == false)
        #expect(SharedProjectPresentation.memberRoleLabel(.member, locale: Locale(identifier: "ar")).isEmpty == false)
        #expect(ProjectInviteLifetimePolicy.lifetimeDays == 7)
    }

    @Test("Joined-project local shell mapping and duplicate avoidance")
    func joinedProjectLocalShell() {
        let id = UUID()
        let shell = JoinedSharedProjectShellPolicy.make(
            projectID: id,
            title: "  Roadmap  ",
            description: " Notes ",
            color: "#5B8DEF",
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(shell.id == id)
        #expect(shell.title == "Roadmap")
        #expect(shell.remoteProjectID == id.uuidString)
        #expect(shell.colorHex == ProjectColorCatalog.sanitized("#5B8DEF"))

        #expect(
            JoinedSharedProjectShellPolicy.shouldCreateLocalShell(
                existingLocalSharingMode: nil,
                existingRemoteProjectID: nil,
                projectID: id
            )
        )
        #expect(
            !JoinedSharedProjectShellPolicy.shouldCreateLocalShell(
                existingLocalSharingMode: .shared,
                existingRemoteProjectID: id.uuidString,
                projectID: id
            )
        )
        #expect(
            JoinedSharedProjectShellPolicy.shouldCreateLocalShell(
                existingLocalSharingMode: .personal,
                existingRemoteProjectID: nil,
                projectID: id
            )
        )
    }

    @Test("Initials presentation for remote member snapshots")
    func remoteMemberInitials() {
        #expect(ProfileAvatarInitialsPolicy.initials(from: "Jameel Alkhlq") == "JA")
        #expect(ProfileAvatarInitialsPolicy.initials(from: "Anas Hamad") == "AH")
        #expect(ProfileAvatarInitialsPolicy.initials(from: "") == "")
    }

    @Test("Share message localization includes invite URL")
    func shareMessageIncludesURL() {
        let token = ProjectInviteTokenGenerator.generate()
        let url = ProjectInviteURLBuilder.url(token: token)!
        let en = ProjectInviteURLBuilder.shareMessage(url: url, locale: Locale(identifier: "en"))
        let ar = ProjectInviteURLBuilder.shareMessage(url: url, locale: Locale(identifier: "ar"))
        #expect(en.contains(url.absoluteString))
        #expect(ar.contains(url.absoluteString))
        #expect(en.lowercased().contains("todoshi"))
    }

    @Test("User-facing invite errors resolve to localized strings")
    func inviteErrorMessages() {
        for error in [
            CollaborationError.inviteInvalid,
            .inviteExpired,
            .inviteAlreadyUsed,
            .inviteRevoked,
            .inviteCreateFailed,
            .inviteAcceptFailed,
            .inviteNotOwner,
        ] {
            #expect(UserFacingError.message(for: error).isEmpty == false)
        }
    }

    @Test("Pending invite auth continuation: remember token then resume after sign-in")
    func pendingInviteAuthContinuation() {
        let token = ProjectInviteTokenGenerator.generate()
        #expect(ProjectInviteTokenGenerator.isValidFormat(token))
        // Mirrors AuthSessionController: store while signed out; consume only when authenticated.
        var pending: String? = token
        let requirementWhileSignedOut = CollaborationAuthGate.requirement(for: nil)
        #expect(requirementWhileSignedOut == .requiresAuthentication)
        #expect(pending == token)

        let session = CollaborationSession(
            user: CollaborationUser(id: "uid-1", displayName: "Member", email: nil)
        )
        let requirementAfterSignIn = CollaborationAuthGate.requirement(for: session)
        if case .authenticated = requirementAfterSignIn {
            let consumed = pending
            pending = nil
            #expect(consumed == token)
            #expect(pending == nil)
            #expect(TodoshiDeepLink(url: ProjectInviteURLBuilder.url(token: consumed!)!) == .invite(token: token))
        } else {
            Issue.record("Expected authenticated requirement after session")
        }
    }

    @Test("Temporary no-task-sync notice key retained for catalog but Phase 4 removes UI usage")
    func temporaryNoTaskSyncNotice() {
        // Key may remain in catalogs; product UI no longer shows it after Phase 4 sync.
        #expect(ProjectInvitePresentation.temporaryNoTaskSyncNoticeKey == "project.invite.joinedNoTaskSync")
    }
}
