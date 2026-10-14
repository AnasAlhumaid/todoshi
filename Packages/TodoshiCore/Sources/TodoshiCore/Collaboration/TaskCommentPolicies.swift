import Foundation

/// Firestore-backed task comment (not stored in SwiftData).
public struct TaskComment: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let authorUID: String
    public let authorDisplayName: String
    public let body: String
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    public init(
        id: UUID,
        authorUID: String,
        authorDisplayName: String,
        body: String,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.authorUID = authorUID
        self.authorDisplayName = authorDisplayName
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool { deletedAt != nil }
}

/// Cloud transport for `projects/{projectId}/tasks/{taskId}/comments/{commentId}`.
public struct FirestoreTaskCommentDTO: Codable, Sendable, Equatable {
    public let id: UUID
    public let authorUID: String
    public let authorDisplayName: String
    public let body: String
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    public init(
        id: UUID,
        authorUID: String,
        authorDisplayName: String,
        body: String,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.authorUID = authorUID
        self.authorDisplayName = authorDisplayName
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var documentID: String { id.uuidString }
}

public enum TaskCommentBodyPolicy: Sendable {
    public static let maxLength = 4000

    public enum Validation: Sendable, Equatable {
        case valid(trimmed: String)
        case empty
        case tooLong
    }

    public static func validate(_ raw: String) -> Validation {
        let trimmed = FieldValidation.trimmed(raw)
        if trimmed.isEmpty { return .empty }
        if trimmed.count > maxLength { return .tooLong }
        return .valid(trimmed: trimmed)
    }

    public static func isValid(_ raw: String) -> Bool {
        if case .valid = validate(raw) { return true }
        return false
    }
}

public enum TaskCommentVisibilityPolicy: Sendable {
    /// Phase 5 hides soft-deleted comments entirely (no placeholder).
    public static func isVisible(_ comment: TaskComment) -> Bool {
        comment.deletedAt == nil
    }

    public static func visibleComments(from comments: [TaskComment]) -> [TaskComment] {
        comments.filter(isVisible)
    }
}

public enum TaskCommentOrderingPolicy: Sendable {
    /// Conversation order: createdAt ascending (stable by id).
    public static func ordered(_ comments: [TaskComment]) -> [TaskComment] {
        comments.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public static func orderedVisible(from comments: [TaskComment]) -> [TaskComment] {
        ordered(TaskCommentVisibilityPolicy.visibleComments(from: comments))
    }
}

public enum TaskCommentInitialsPolicy: Sendable {
    public static func initials(from displayName: String, fallbackUID: String = "") -> String {
        let trimmed = FieldValidation.trimmed(displayName)
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if parts.count >= 2,
           let a = parts[0].first,
           let b = parts[1].first {
            return String([a, b]).uppercased()
        }
        if let first = parts.first, !first.isEmpty {
            let chars = Array(first)
            if chars.count >= 2 {
                return String(chars.prefix(2)).uppercased()
            }
            return String(chars[0]).uppercased()
        }
        let uid = FieldValidation.trimmed(fallbackUID)
        if let c = uid.first {
            return String(c).uppercased()
        }
        return "?"
    }
}

public enum TaskCommentModerationPolicy: Sendable {
    public static func canEditBody(
        viewerUID: String?,
        commentAuthorUID: String
    ) -> Bool {
        guard let viewerUID, !viewerUID.isEmpty else { return false }
        return viewerUID == commentAuthorUID
    }

    /// Author may soft-delete own; project owner may soft-delete any.
    public static func canSoftDelete(
        viewerUID: String?,
        viewerRole: ProjectMemberRole?,
        commentAuthorUID: String
    ) -> Bool {
        guard let viewerUID, !viewerUID.isEmpty else { return false }
        if viewerUID == commentAuthorUID { return true }
        return viewerRole == .owner
    }

    /// Owner moderation is soft-delete only — never rewrite another author's body.
    public static func ownerMayRewriteForeignBody() -> Bool { false }
}

/// UI / presentation permissions aligned with Phase 5 role policy (rules remain authoritative).
public enum SharedProjectRolePermissions: Sendable {
    public static func canEditProjectMetadata(role: ProjectMemberRole?) -> Bool {
        role == .owner
    }

    public static func canInviteMembers(role: ProjectMemberRole?) -> Bool {
        ProjectInvitePresentation.canInviteMembers(role: role)
    }

    public static func canCreateComments(role: ProjectMemberRole?) -> Bool {
        role == .owner || role == .member
    }

    public static func canMutateTasks(role: ProjectMemberRole?) -> Bool {
        role == .owner || role == .member
    }

    public static func displayNameSnapshot(
        preferred: String?,
        email: String? = nil,
        uid: String
    ) -> String {
        _ = email
        return CollaborationDisplayNamePolicy.collaborationSnapshot(preferred: preferred, uid: uid)
    }
}

public enum TaskCommentMapping: Sendable {
    public static func comment(from dto: FirestoreTaskCommentDTO) -> TaskComment {
        TaskComment(
            id: dto.id,
            authorUID: dto.authorUID,
            authorDisplayName: dto.authorDisplayName,
            body: dto.body,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            deletedAt: dto.deletedAt
        )
    }

    public static func dto(from comment: TaskComment) -> FirestoreTaskCommentDTO {
        FirestoreTaskCommentDTO(
            id: comment.id,
            authorUID: comment.authorUID,
            authorDisplayName: comment.authorDisplayName,
            body: comment.body,
            createdAt: comment.createdAt,
            updatedAt: comment.updatedAt,
            deletedAt: comment.deletedAt
        )
    }
}

public enum TaskCommentStrings: Sendable {
    public static var comments: String { TodoshiL10n.tr("task.comments") }
    public static var placeholder: String { TodoshiL10n.tr("task.comments.placeholder") }
    public static var empty: String { TodoshiL10n.tr("task.comments.empty") }
    public static var send: String { TodoshiL10n.tr("task.comments.send") }
    public static var editTitle: String { TodoshiL10n.tr("task.comments.editTitle") }
    public static var deleteConfirm: String { TodoshiL10n.tr("task.comments.deleteConfirm") }
    public static var emptyBodyError: String { TodoshiL10n.tr("task.comments.error.empty") }
    public static var tooLongError: String { TodoshiL10n.tr("task.comments.error.tooLong") }
    public static var postFailed: String { TodoshiL10n.tr("task.comments.error.postFailed") }
}
