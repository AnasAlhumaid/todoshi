import Foundation

/// Snapshot of a shared root task relevant to member-removal cleanup.
public struct MemberRemovalTaskSnapshot: Sendable, Equatable {
    public let id: String
    public let assigneeUID: String?
    public let editorUIDs: [String]
    public let parentTaskId: String?
    public let deletedAt: Date?

    public init(
        id: String,
        assigneeUID: String?,
        editorUIDs: [String],
        parentTaskId: String?,
        deletedAt: Date?
    ) {
        self.id = id
        self.assigneeUID = assigneeUID
        self.editorUIDs = editorUIDs
        self.parentTaskId = parentTaskId
        self.deletedAt = deletedAt
    }
}

public struct MemberRemovalTaskCleanupUpdate: Sendable, Equatable {
    public let taskID: String
    public let clearAssignee: Bool
    public let removeEditorUID: Bool

    public init(taskID: String, clearAssignee: Bool, removeEditorUID: Bool) {
        self.taskID = taskID
        self.clearAssignee = clearAssignee
        self.removeEditorUID = removeEditorUID
    }
}

public struct MemberRemovalTaskCleanupPlan: Sendable, Equatable {
    public let updates: [MemberRemovalTaskCleanupUpdate]

    public init(updates: [MemberRemovalTaskCleanupUpdate]) {
        self.updates = updates
    }
}

/// Phase 9A — deterministic task cleanup before membership revoke.
public enum MemberRemovalCleanupPolicy: Sendable {
    /// Firestore batch limit headroom (seed policy uses the same ceiling).
    public static let maxTaskWritesPerChunk = SharedProjectSeedPolicy.maxWritesPerBatch

    public static func ownerCanRemoveMember(
        ownerUID: String,
        targetUID: String,
        targetRole: ProjectMemberRole
    ) -> Bool {
        guard ownerUID != targetUID else { return false }
        guard targetRole != .owner else { return false }
        return !ownerUID.isEmpty && !targetUID.isEmpty
    }

    public static func memberCanLeave(
        actingUID: String,
        memberUID: String,
        memberRole: ProjectMemberRole
    ) -> Bool {
        guard actingUID == memberUID else { return false }
        guard memberRole != .owner else { return false }
        return !actingUID.isEmpty
    }

    /// Merges assignee and editor query hits by task document ID.
    public static func deduplicatedLiveRootTasks(
        assigneeMatches: [MemberRemovalTaskSnapshot],
        editorMatches: [MemberRemovalTaskSnapshot]
    ) -> [MemberRemovalTaskSnapshot] {
        var merged: [String: MemberRemovalTaskSnapshot] = [:]
        for task in assigneeMatches + editorMatches where isLiveRootTask(task) {
            merged[task.id] = task
        }
        return merged.values.sorted { $0.id < $1.id }
    }

    public static func planCleanup(
        targetUID: String,
        tasks: [MemberRemovalTaskSnapshot]
    ) -> MemberRemovalTaskCleanupPlan {
        let updates = tasks.compactMap { task -> MemberRemovalTaskCleanupUpdate? in
            guard isLiveRootTask(task) else { return nil }
            let clearAssignee = task.assigneeUID == targetUID
            let removeEditor = task.editorUIDs.contains(targetUID)
            guard clearAssignee || removeEditor else { return nil }
            return MemberRemovalTaskCleanupUpdate(
                taskID: task.id,
                clearAssignee: clearAssignee,
                removeEditorUID: removeEditor
            )
        }
        return MemberRemovalTaskCleanupPlan(updates: updates)
    }

    /// Returns `nil` when the task is already clean (idempotent).
    public static func cleanupFields(
        targetUID: String,
        task: MemberRemovalTaskSnapshot
    ) -> (clearAssignee: Bool, editorUIDs: [String])? {
        guard isLiveRootTask(task) else { return nil }
        let shouldClearAssignee = task.assigneeUID == targetUID
        let shouldRemoveEditor = task.editorUIDs.contains(targetUID)
        guard shouldClearAssignee || shouldRemoveEditor else { return nil }

        let nextEditors = shouldRemoveEditor
            ? task.editorUIDs.filter { $0 != targetUID }
            : task.editorUIDs
        return (shouldClearAssignee, nextEditors)
    }

    public static func chunkUpdates<T>(
        _ updates: [T],
        chunkSize: Int = maxTaskWritesPerChunk
    ) -> [[T]] {
        guard chunkSize > 0 else { return updates.isEmpty ? [] : [updates] }
        guard !updates.isEmpty else { return [] }
        var chunks: [[T]] = []
        var index = 0
        while index < updates.count {
            let end = min(index + chunkSize, updates.count)
            chunks.append(Array(updates[index..<end]))
            index = end
        }
        return chunks
    }

    private static func isLiveRootTask(_ task: MemberRemovalTaskSnapshot) -> Bool {
        task.deletedAt == nil
            && (task.parentTaskId == nil || task.parentTaskId?.isEmpty == true)
    }
}

/// Local cache behavior when collaboration access ends.
public enum SharedProjectMemberEvictionPolicy: Sendable {
    public static let removesLocalSharedCache = true
    public static let convertsToPersonal = false
    public static let preservesHistoricalSnapshotsInCloud = true
}

public enum SharedProjectAccessLossCenter {
    public static let notification = Notification.Name("com.anashamad.Todoshi.sharedProjectAccessLost")

    public enum UserInfoKey {
        public static let projectID = "projectID"
        public static let message = "message"
        public static let voluntary = "voluntary"
    }

    public static func post(projectID: UUID, message: String, voluntary: Bool) {
        NotificationCenter.default.post(
            name: notification,
            object: nil,
            userInfo: [
                UserInfoKey.projectID: projectID.uuidString,
                UserInfoKey.message: message,
                UserInfoKey.voluntary: voluntary,
            ]
        )
    }
}
