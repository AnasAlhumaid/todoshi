import CryptoKit
import Foundation

/// Phase 4 content schema for shared project cloud payloads.
public enum SharedProjectContentSchema: Sendable {
    /// v1: initial Phase 4 cloud content.
    /// v2: ensures flat-collection subtasks are represented remotely (repair for already-seeded projects).
    public static let currentVersion = 2
}

/// Conflict resolution: remote authoritative timestamps win (last-write-wins).
public enum SharedProjectConflictPolicy: Sendable {
    public enum Winner: Sendable, Equatable {
        case remote
        case local
        case equal
    }

    public static func winner(
        localRemoteUpdatedAt: Date?,
        incomingRemoteUpdatedAt: Date?
    ) -> Winner {
        switch (localRemoteUpdatedAt, incomingRemoteUpdatedAt) {
        case (nil, nil):
            // No authoritative timestamps yet — allow apply; caller must not invent client clocks.
            return .remote
        case (nil, .some):
            return .remote
        case (.some, nil):
            // Incoming snapshot lacks updatedAt (e.g. unresolved serverTimestamp). Do not
            // treat local as newer and do not apply a synthetic Date.now as remote time.
            return .local
        case let (local?, incoming?):
            if incoming > local { return .remote }
            if incoming < local { return .local }
            return .equal
        }
    }

    /// Soft-deleted remote entities always win over stale local live copies.
    public static func shouldApplyRemoteSoftDelete(
        remoteDeletedAt: Date?,
        localExists: Bool
    ) -> Bool {
        remoteDeletedAt != nil && localExists
    }
}

/// Cloud-safe task resources. Binary attachments stay device-local until Storage ships.
public enum SharedTaskResourceSyncPolicy: Sendable {
    public static let cloudSyncableKinds: Set<TaskResourceKind> = [
        .link, .text, .codeSnippet, .terminalCommand
    ]

    public static func isCloudSyncable(_ kind: TaskResourceKind) -> Bool {
        cloudSyncableKinds.contains(kind)
    }

    public static func shouldExcludeFromCloudSeed(_ kind: TaskResourceKind) -> Bool {
        kind.isFileBacked
    }

    public static let deferredBinaryMessageKey = "project.share.binaryResourceDeferred"
}

/// Sign-out / account-switch: shared cache is bound to a Firebase UID.
public enum SharedProjectAccountIsolationPolicy: Sendable {
    /// Hide shared projects while signed out; never convert to personal.
    public static let hideSharedProjectsWhenSignedOut = true

    /// Block shared mutations without an authenticated collaboration identity.
    public static let requireAuthenticationForSharedMutation = true

    public static func isVisible(
        sharingMode: ProjectSharingMode,
        collaborationOwnerUID: String?,
        currentUID: String?
    ) -> Bool {
        guard sharingMode == .shared else { return true }
        guard let currentUID, !currentUID.isEmpty else {
            return !hideSharedProjectsWhenSignedOut
        }
        guard let owner = collaborationOwnerUID, !owner.isEmpty else {
            // Legacy shared shells without owner context stay hidden until rebound.
            return false
        }
        return owner == currentUID
    }

    public static func canMutateShared(
        sharingMode: ProjectSharingMode,
        currentUID: String?
    ) -> Bool {
        guard sharingMode == .shared else { return true }
        guard requireAuthenticationForSharedMutation else { return true }
        return currentUID != nil && !(currentUID?.isEmpty ?? true)
    }
}

/// Owner-only initial content seeding for Phase 2/3 projects that lack cloud tasks.
public enum SharedProjectSeedPolicy: Sendable {
    public static let maxWritesPerBatch = 400

    public static func needsOwnerSeed(
        isOwner: Bool,
        contentSeededAt: Date?,
        contentSchemaVersion: Int?
    ) -> Bool {
        guard isOwner else { return false }
        if contentSeededAt != nil { return false }
        // Unset marker means pre-Phase-4 remote project still needs content upload.
        return true
    }

    /// Already-seeded projects at schema < current need an idempotent merge repair (e.g. missing subtasks).
    public static func needsOwnerContentRepair(
        isOwner: Bool,
        contentSeededAt: Date?,
        contentSchemaVersion: Int?
    ) -> Bool {
        guard isOwner, contentSeededAt != nil else { return false }
        return (contentSchemaVersion ?? 1) < SharedProjectContentSchema.currentVersion
    }

    /// Prefer explicit seed marker; empty tasks alone never proves seeding finished.
    public static func isContentReady(contentSeededAt: Date?) -> Bool {
        contentSeededAt != nil
    }

    /// Seed/repair must include every live TaskItem (roots and subtasks). Never filter to roots only.
    public static func tasksForCloudUpload(from projectTasks: [TaskItem]) -> [TaskItem] {
        projectTasks
            .filter { $0.deletedAt == nil }
            .sorted { lhs, rhs in
                // Parents before children so remote parentTaskId integrity checks can succeed.
                let lhsRoot = lhs.parentTask == nil
                let rhsRoot = rhs.parentTask == nil
                if lhsRoot != rhsRoot { return lhsRoot && !rhsRoot }
                return lhs.createdAt < rhs.createdAt
            }
    }
}

/// Parent linking for flat-collection task sync. Children must not be dropped when parents arrive later.
public enum SharedProjectHierarchyReconcilePolicy: Sendable {
    public struct ParentLinkResult: Sendable, Equatable {
        /// Immediate SwiftData parent to attach (nil when unknown or root).
        public let attachParentID: UUID?
        /// Remembered desired parent when the parent TaskItem is not local yet.
        public let pendingParentID: UUID?

        public init(attachParentID: UUID?, pendingParentID: UUID?) {
            self.attachParentID = attachParentID
            self.pendingParentID = pendingParentID
        }
    }

    /// Preserve `parentTaskId` even when the parent document has not been reconciled yet.
    public static func parentLink(
        parentTaskId: UUID?,
        knownLocalTaskIDs: Set<UUID>
    ) -> ParentLinkResult {
        guard let parentTaskId else {
            return ParentLinkResult(attachParentID: nil, pendingParentID: nil)
        }
        if knownLocalTaskIDs.contains(parentTaskId) {
            return ParentLinkResult(attachParentID: parentTaskId, pendingParentID: nil)
        }
        return ParentLinkResult(attachParentID: nil, pendingParentID: parentTaskId)
    }

    /// Resolve deferred child→parent links once parents exist locally.
    public static func resolvePending(
        pendingByChild: [UUID: UUID],
        knownLocalTaskIDs: Set<UUID>
    ) -> (resolved: [UUID: UUID], stillPending: [UUID: UUID]) {
        var resolved: [UUID: UUID] = [:]
        var stillPending: [UUID: UUID] = [:]
        for (childID, parentID) in pendingByChild {
            if knownLocalTaskIDs.contains(parentID) {
                resolved[childID] = parentID
            } else {
                stillPending[childID] = parentID
            }
        }
        return (resolved, stillPending)
    }
}

public enum SharedProjectPermissionLossPolicy: Sendable {
    /// Stop listeners; mark unavailable; do not convert to personal.
    public static let convertToPersonalOnPermissionDenied = false
    public static let stopListenersOnPermissionDenied = true
}

/// Deterministic successor UUID so two devices cannot mint different next occurrences.
public enum SharedRecurrenceSuccessorIdentity: Sendable {
    /// UUID derived from series + generation (SHA-256 truncated to 16 bytes).
    public static func successorID(seriesID: UUID, generation: Int) -> UUID {
        let material = "todoshi.recurrence.v1:\(seriesID.uuidString.lowercased()):\(generation)"
        let digest = SHA256.hash(data: Data(material.utf8))
        var bytes = Array(digest.prefix(16))
        // RFC 4122 variant/version bits for a name-based-like UUID.
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // variant
        let uuid = NSUUID(uuidBytes: bytes) as UUID
        return uuid
    }
}

/// Hook surface so repositories stay free of Firebase imports.
public enum SharedProjectMutationHook: Sendable {
    public enum Event: Sendable, Equatable {
        case projectMetadata(UUID)
        case taskUpsert(projectID: UUID, taskID: UUID)
        case taskSoftDelete(projectID: UUID, taskID: UUID)
        case checklistChanged(projectID: UUID, taskID: UUID)
        case labelsChanged(projectID: UUID)
        case resourceChanged(projectID: UUID, taskID: UUID)
        case projectDeleted(UUID)
        /// Board columns changed (owner only; stored in `/projectBoards/{projectId}`).
        case boardColumns(UUID)
        /// A root task moved to another board column (`/projectBoards/{projectId}/placements/{taskId}`).
        case taskColumn(projectID: UUID, taskID: UUID)
    }

    nonisolated(unsafe) public static var handler: (@Sendable (Event) -> Void)?

    public static func emit(_ event: Event) {
        handler?(event)
    }
}
