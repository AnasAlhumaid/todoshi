import Foundation
import Testing
@testable import TodoshiCore

struct Phase5CommentsTests {
    @Test("Comment body trimming, empty, and max length")
    func bodyValidation() {
        #expect(TaskCommentBodyPolicy.maxLength == 4000)
        guard case .valid(let trimmed) = TaskCommentBodyPolicy.validate("  hello  ") else {
            Issue.record("expected valid")
            return
        }
        #expect(trimmed == "hello")
        #expect(TaskCommentBodyPolicy.validate("   ") == .empty)
        #expect(TaskCommentBodyPolicy.validate("") == .empty)
        let tooLong = String(repeating: "a", count: 4001)
        #expect(TaskCommentBodyPolicy.validate(tooLong) == .tooLong)
        #expect(TaskCommentBodyPolicy.isValid("ok"))
        #expect(!TaskCommentBodyPolicy.isValid("  "))
    }

    @Test("Moderation: author edit/delete; owner soft-delete only")
    func moderationPolicy() {
        #expect(TaskCommentModerationPolicy.canEditBody(viewerUID: "a", commentAuthorUID: "a"))
        #expect(!TaskCommentModerationPolicy.canEditBody(viewerUID: "a", commentAuthorUID: "b"))
        #expect(!TaskCommentModerationPolicy.canEditBody(viewerUID: nil, commentAuthorUID: "a"))

        #expect(
            TaskCommentModerationPolicy.canSoftDelete(
                viewerUID: "a",
                viewerRole: .member,
                commentAuthorUID: "a"
            )
        )
        #expect(
            !TaskCommentModerationPolicy.canSoftDelete(
                viewerUID: "a",
                viewerRole: .member,
                commentAuthorUID: "b"
            )
        )
        #expect(
            TaskCommentModerationPolicy.canSoftDelete(
                viewerUID: "owner",
                viewerRole: .owner,
                commentAuthorUID: "b"
            )
        )
        #expect(!TaskCommentModerationPolicy.ownerMayRewriteForeignBody())
    }

    @Test("Role presentation permissions")
    func rolePermissions() {
        #expect(SharedProjectRolePermissions.canEditProjectMetadata(role: .owner))
        #expect(!SharedProjectRolePermissions.canEditProjectMetadata(role: .member))
        #expect(SharedProjectRolePermissions.canInviteMembers(role: .owner))
        #expect(!SharedProjectRolePermissions.canInviteMembers(role: .member))
        #expect(SharedProjectRolePermissions.canCreateComments(role: .member))
        #expect(SharedProjectRolePermissions.canMutateTasks(role: .member))
        #expect(
            SharedProjectRolePermissions.displayNameSnapshot(
                preferred: " Ana ",
                email: "a@b.com",
                uid: "uid1"
            ) == "Ana"
        )
        #expect(
            SharedProjectRolePermissions.displayNameSnapshot(
                preferred: nil,
                email: "a@b.com",
                uid: "uid1"
            ) == TodoshiL10n.tr("project.members.unnamed")
        )
    }

    @Test("DTO ↔ TaskComment mapping and soft-delete visibility")
    func mappingAndVisibility() {
        let id = UUID()
        let dto = FirestoreTaskCommentDTO(
            id: id,
            authorUID: "u1",
            authorDisplayName: "Sam",
            body: "Hi",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let comment = TaskCommentMapping.comment(from: dto)
        #expect(comment.id == id)
        #expect(comment.authorDisplayName == "Sam")
        #expect(TaskCommentVisibilityPolicy.isVisible(comment))

        let roundTrip = TaskCommentMapping.dto(from: comment)
        #expect(roundTrip == dto)

        let deleted = TaskComment(
            id: id,
            authorUID: "u1",
            authorDisplayName: "Sam",
            body: "Hi",
            createdAt: .now,
            updatedAt: .now,
            deletedAt: .now
        )
        #expect(!TaskCommentVisibilityPolicy.isVisible(deleted))
        #expect(TaskCommentVisibilityPolicy.visibleComments(from: [comment, deleted]) == [comment])
    }

    @Test("Initials and conversation ordering")
    func initialsAndOrdering() {
        #expect(TaskCommentInitialsPolicy.initials(from: "Ada Lovelace") == "AL")
        #expect(TaskCommentInitialsPolicy.initials(from: "Madonna") == "MA")
        #expect(TaskCommentInitialsPolicy.initials(from: "", fallbackUID: "xyz") == "X")

        let older = TaskComment(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            authorUID: "a",
            authorDisplayName: "A",
            body: "1",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = TaskComment(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            authorUID: "b",
            authorDisplayName: "B",
            body: "2",
            createdAt: Date(timeIntervalSince1970: 2),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let deleted = TaskComment(
            id: UUID(),
            authorUID: "c",
            authorDisplayName: "C",
            body: "x",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            deletedAt: .now
        )
        #expect(TaskCommentOrderingPolicy.orderedVisible(from: [newer, deleted, older]).map(\.body) == ["1", "2"])
    }
}
