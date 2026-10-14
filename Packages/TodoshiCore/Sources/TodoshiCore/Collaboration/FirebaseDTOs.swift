import Foundation

public struct FirebaseProjectDTO: Codable, Sendable, Equatable {
    public let id: UUID
    public let ownerId: String
    public let title: String
    public let description: String
    public let color: String
    public let position: Double
    public let memberIds: [String]
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?
    /// Phase 4 content schema version (1+). Nil on legacy Phase 2/3 projects.
    public let contentSchemaVersion: Int?
    /// Set only after owner finishes initial supported-content seed.
    public let contentSeededAt: Date?
    /// Phase 8 — `tasks` | `checklist`. Nil means legacy → treat as tasks.
    public let projectTypeRaw: String?

    public init(
        id: UUID,
        ownerId: String,
        title: String,
        description: String,
        color: String,
        position: Double,
        memberIds: [String],
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        contentSchemaVersion: Int? = nil,
        contentSeededAt: Date? = nil,
        projectTypeRaw: String? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.description = description
        self.color = color
        self.position = position
        self.memberIds = memberIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.contentSchemaVersion = contentSchemaVersion
        self.contentSeededAt = contentSeededAt
        self.projectTypeRaw = projectTypeRaw
    }

    public var documentID: String { id.uuidString }

    public var resolvedProjectType: ProjectType {
        ProjectType.resolve(projectTypeRaw)
    }

    public var isContentReady: Bool {
        SharedProjectSeedPolicy.isContentReady(contentSeededAt: contentSeededAt)
    }
}

public struct FirebaseProjectMemberDTO: Codable, Sendable, Equatable {
    public let userId: String
    public let role: ProjectMemberRole
    public let displayName: String?
    public let joinedAt: Date
    public let acceptedInviteId: String?
    /// Phase 6: `full` | `restricted`. Nil means legacy → treat as full.
    public let accessLevel: ProjectMemberAccessLevel?

    public init(
        userId: String,
        role: ProjectMemberRole,
        displayName: String? = nil,
        joinedAt: Date,
        acceptedInviteId: String? = nil,
        accessLevel: ProjectMemberAccessLevel? = nil
    ) {
        self.userId = userId
        self.role = role
        self.displayName = displayName
        self.joinedAt = joinedAt
        self.acceptedInviteId = acceptedInviteId
        self.accessLevel = accessLevel
    }

    public var documentID: String { userId }

    public var resolvedAccessLevel: ProjectMemberAccessLevel {
        if role == .owner { return .full }
        return ProjectMemberAccessLevel.resolved(raw: accessLevel?.rawValue)
    }
}

/// Capability invite stored at `projectInvites/{token}` — the token is the document ID (bearer secret).
public struct FirebaseProjectInviteDTO: Codable, Sendable, Equatable {
    public let projectId: String
    public let createdBy: String
    public let role: ProjectMemberRole
    public let projectTitle: String
    public let inviterDisplayName: String?
    public let createdAt: Date
    public let expiresAt: Date
    public let acceptedAt: Date?
    public let acceptedBy: String?
    public let revokedAt: Date?

    public init(
        projectId: String,
        createdBy: String,
        role: ProjectMemberRole = .member,
        projectTitle: String,
        inviterDisplayName: String? = nil,
        createdAt: Date,
        expiresAt: Date,
        acceptedAt: Date? = nil,
        acceptedBy: String? = nil,
        revokedAt: Date? = nil
    ) {
        self.projectId = projectId
        self.createdBy = createdBy
        self.role = role
        self.projectTitle = projectTitle
        self.inviterDisplayName = inviterDisplayName
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.acceptedAt = acceptedAt
        self.acceptedBy = acceptedBy
        self.revokedAt = revokedAt
    }
}

public enum FirebaseInviteSecurityPolicy: Sendable {
    /// Raw invite tokens are the Firestore document ID and must never be stored as a field.
    public static let collectionName = "projectInvites"
    public static let bearerTokenIsDocumentID = true
}

/// Cloud transport for tasks. Separate from SwiftData `TaskItem`.
public struct FirestoreTaskDTO: Codable, Sendable, Equatable {
    public let id: UUID
    public let projectId: UUID
    public let parentTaskId: UUID?
    public let title: String
    public let description: String
    public let notes: String
    public let statusRaw: String
    public let priorityRaw: String
    public let dueDate: Date?
    public let reminderDate: Date?
    public let position: Double
    public let completedAt: Date?
    /// Member who marked Done (Phase 8.1). Independent of `assigneeUID`.
    public let completedByUID: String?
    /// Membership displayName snapshot at completion.
    public let completedByDisplayName: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?
    public let labelIds: [UUID]
    public let recurrenceRuleRaw: String?
    public let recurrenceInterval: Int?
    public let recurrenceSeriesID: UUID?
    public let recurrenceGeneration: Int
    public let nextOccurrenceID: UUID?
    public let previousOccurrenceID: UUID?
    /// When false, `updatedAt` is a local placeholder and must not stamp `remoteUpdatedAt`.
    public let hasAuthoritativeRemoteUpdatedAt: Bool
    /// UIDs of restricted members allowed to edit this root task (and its subtasks).
    public let editorUIDs: [String]
    /// Member responsible for this root task. Always nil for subtasks (Phase 7).
    public let assigneeUID: String?
    /// Latest collaboration activity (root tasks only).
    public let lastActivityAt: Date?
    public let lastActivityByUID: String?
    public let lastActivityKindRaw: String?

    public init(
        id: UUID,
        projectId: UUID,
        parentTaskId: UUID? = nil,
        title: String,
        description: String = "",
        notes: String = "",
        statusRaw: String,
        priorityRaw: String,
        dueDate: Date? = nil,
        reminderDate: Date? = nil,
        position: Double,
        completedAt: Date? = nil,
        completedByUID: String? = nil,
        completedByDisplayName: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        labelIds: [UUID] = [],
        recurrenceRuleRaw: String? = nil,
        recurrenceInterval: Int? = nil,
        recurrenceSeriesID: UUID? = nil,
        recurrenceGeneration: Int = 0,
        nextOccurrenceID: UUID? = nil,
        previousOccurrenceID: UUID? = nil,
        hasAuthoritativeRemoteUpdatedAt: Bool = true,
        editorUIDs: [String] = [],
        assigneeUID: String? = nil,
        lastActivityAt: Date? = nil,
        lastActivityByUID: String? = nil,
        lastActivityKindRaw: String? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.parentTaskId = parentTaskId
        self.title = title
        self.description = description
        self.notes = notes
        self.statusRaw = statusRaw
        self.priorityRaw = priorityRaw
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.position = position
        self.completedAt = completedAt
        self.completedByUID = completedByUID
        self.completedByDisplayName = completedByDisplayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.labelIds = labelIds
        self.recurrenceRuleRaw = recurrenceRuleRaw
        self.recurrenceInterval = recurrenceInterval
        self.recurrenceSeriesID = recurrenceSeriesID
        self.recurrenceGeneration = recurrenceGeneration
        self.nextOccurrenceID = nextOccurrenceID
        self.previousOccurrenceID = previousOccurrenceID
        self.hasAuthoritativeRemoteUpdatedAt = hasAuthoritativeRemoteUpdatedAt
        self.editorUIDs = editorUIDs
        // Subtask assignment is never independent; responsibility resolves through the root.
        self.assigneeUID = parentTaskId == nil ? assigneeUID : nil
        self.lastActivityAt = parentTaskId == nil ? lastActivityAt : nil
        self.lastActivityByUID = parentTaskId == nil ? lastActivityByUID : nil
        self.lastActivityKindRaw = parentTaskId == nil ? lastActivityKindRaw : nil
    }

    public var documentID: String { id.uuidString }

    public var authoritativeRemoteUpdatedAt: Date? {
        hasAuthoritativeRemoteUpdatedAt ? updatedAt : nil
    }
}

/// Backward-compatible alias used by earlier collaboration tests.
public typealias FirebaseTaskDTO = FirestoreTaskDTO

public struct FirestoreChecklistItemDTO: Codable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let isCompleted: Bool
    public let position: Double
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    public init(
        id: UUID,
        title: String,
        isCompleted: Bool,
        position: Double,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var documentID: String { id.uuidString }
}

public struct FirestoreLabelDTO: Codable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let color: String
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    public init(
        id: UUID,
        name: String,
        color: String,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var documentID: String { id.uuidString }
}

public struct FirestoreTaskResourceDTO: Codable, Sendable, Equatable {
    public let id: UUID
    public let kindRaw: String
    public let title: String
    public let body: String?
    public let externalURLString: String?
    public let languageIdentifier: String?
    public let position: Double
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    public init(
        id: UUID,
        kindRaw: String,
        title: String,
        body: String? = nil,
        externalURLString: String? = nil,
        languageIdentifier: String? = nil,
        position: Double,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.title = title
        self.body = body
        self.externalURLString = externalURLString
        self.languageIdentifier = languageIdentifier
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var documentID: String { id.uuidString }

    public var kind: TaskResourceKind? {
        TaskResourceKind.parse(kindRaw)
    }

    public var isCloudAllowed: Bool {
        guard let kind else { return false }
        return SharedTaskResourceSyncPolicy.isCloudSyncable(kind)
    }
}

public enum FirebaseIdentifierPolicy: Sendable {
    /// Firebase Auth user IDs remain opaque strings and must not be converted to UUID.
    public static func isValidFirebaseUserID(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func firestoreDocumentID(for entityID: UUID) -> String {
        entityID.uuidString
    }
}

/// Maps between SwiftData task snapshots and Firestore DTOs (no Firebase imports).
public enum FirestoreTaskMapping: Sendable {
    public static func dto(from task: TaskItem) -> FirestoreTaskDTO? {
        guard let project = task.project else { return nil }
        let labels = (task.labels ?? []).map(\.id).sorted { $0.uuidString < $1.uuidString }
        return FirestoreTaskDTO(
            id: task.id,
            projectId: project.id,
            parentTaskId: task.parentTask?.id,
            title: task.title,
            description: task.taskDescription,
            notes: task.notes,
            statusRaw: task.statusRaw,
            priorityRaw: task.priorityRaw,
            dueDate: task.dueDate,
            reminderDate: task.reminderDate,
            position: task.position,
            completedAt: task.completedAt,
            completedByUID: task.completedByUID,
            completedByDisplayName: task.completedByDisplayName,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt,
            deletedAt: task.deletedAt,
            labelIds: labels,
            recurrenceRuleRaw: task.recurrenceRuleRaw,
            recurrenceInterval: task.recurrenceInterval,
            recurrenceSeriesID: task.recurrenceSeriesID,
            recurrenceGeneration: task.recurrenceGeneration,
            nextOccurrenceID: task.nextOccurrenceID,
            previousOccurrenceID: task.previousOccurrenceID,
            editorUIDs: task.isRoot ? (task.editorUIDs ?? []) : [],
            assigneeUID: task.isRoot ? task.assigneeUID : nil,
            lastActivityAt: task.isRoot ? task.lastActivityAt : nil,
            lastActivityByUID: task.isRoot ? task.lastActivityByUID : nil,
            lastActivityKindRaw: task.isRoot ? task.lastActivityKindRaw : nil
        )
    }

    public static func apply(_ dto: FirestoreTaskDTO, to task: TaskItem) {
        task.title = dto.title
        task.taskDescription = dto.description
        task.notes = dto.notes
        task.statusRaw = dto.statusRaw
        task.priorityRaw = dto.priorityRaw
        task.dueDate = dto.dueDate
        task.reminderDate = dto.reminderDate
        task.position = dto.position
        task.completedAt = dto.completedAt
        task.completedByUID = dto.completedByUID
        task.completedByDisplayName = dto.completedByDisplayName
        task.createdAt = dto.createdAt
        task.updatedAt = dto.updatedAt
        task.deletedAt = dto.deletedAt
        // Only stamp remoteUpdatedAt when the DTO carries a real remote time (never Date.now filler).
        if let remote = dto.authoritativeRemoteUpdatedAt {
            task.remoteUpdatedAt = remote
        }
        if dto.parentTaskId == nil {
            task.editorUIDs = dto.editorUIDs
            task.assigneeUID = dto.assigneeUID
            task.lastActivityAt = dto.lastActivityAt
            task.lastActivityByUID = dto.lastActivityByUID
            task.lastActivityKindRaw = dto.lastActivityKindRaw
        } else {
            task.assigneeUID = nil
        }
        task.recurrenceRuleRaw = dto.recurrenceRuleRaw
        task.recurrenceInterval = dto.recurrenceInterval
        task.recurrenceSeriesID = dto.recurrenceSeriesID
        task.recurrenceGeneration = dto.recurrenceGeneration
        task.nextOccurrenceID = dto.nextOccurrenceID
        task.previousOccurrenceID = dto.previousOccurrenceID
    }
}
