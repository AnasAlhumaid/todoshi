import Foundation

/// Latest collaboration activity on a shared root task (not a history feed).
public enum TaskCollaborationActivityKind: String, Codable, Sendable, CaseIterable {
    case taskUpdated
    case statusChanged
    case commentAdded
    case commentEdited
    case subtaskChanged
    case checklistChanged
    case assignmentChanged
    case resourceChanged

    public static func resolve(_ raw: String?) -> TaskCollaborationActivityKind? {
        guard let raw else { return nil }
        return TaskCollaborationActivityKind(rawValue: raw)
    }
}

public enum TaskCollaborationActivityPresentation: Sendable {
    /// Compact unread marker for task/checklist rows (e.g. "● New" / "● جديد").
    public static var unreadBadge: String {
        "● \(TodoshiL10n.tr("task.activity.new"))"
    }
}

public enum TaskCollaborationActivityPolicy: Sendable {
    /// Resolves the root task ID for board-level activity aggregation.
    public static func rootTaskID(for taskID: UUID, parentTaskID: UUID?) -> UUID {
        parentTaskID ?? taskID
    }

    public static func rootTaskID(for task: TaskItem) -> UUID {
        var current: TaskItem? = task
        while let parent = current?.parentTask {
            current = parent
        }
        return current?.id ?? task.id
    }

    public static func hasUnreadActivity(
        isSharedProject: Bool,
        lastActivityAt: Date?,
        lastActivityByUID: String?,
        viewerUID: String?,
        lastSeenAt: Date?
    ) -> Bool {
        guard isSharedProject else { return false }
        guard let lastActivityAt, let lastActivityByUID, let viewerUID else { return false }
        guard lastActivityByUID != viewerUID else { return false }
        guard let lastSeenAt else { return true }
        return lastActivityAt > lastSeenAt
    }

    public static func hasUnreadActivity(
        isSharedProject: Bool,
        task: TaskItem,
        viewerUID: String?
    ) -> Bool {
        let root = task.isRoot ? task : (task.parentTask ?? task)
        let seen = TaskActivitySeenStore.lastSeen(
            uid: viewerUID,
            projectID: root.project?.id,
            rootTaskID: root.id
        )
        return hasUnreadActivity(
            isSharedProject: isSharedProject,
            lastActivityAt: root.lastActivityAt,
            lastActivityByUID: root.lastActivityByUID,
            viewerUID: viewerUID,
            lastSeenAt: seen
        )
    }
}

/// Per-device seen state for collaboration activity. Not synced across devices.
public enum TaskActivitySeenStore: Sendable {
    private static let keyPrefix = "todoshi.collabActivitySeen."

    public static func storageKey(uid: String, projectID: UUID, rootTaskID: UUID) -> String {
        "\(keyPrefix)\(uid).\(projectID.uuidString.lowercased()).\(rootTaskID.uuidString.lowercased())"
    }

    public static func lastSeen(
        uid: String?,
        projectID: UUID?,
        rootTaskID: UUID,
        defaults: UserDefaults = AppLanguageStore.defaults()
    ) -> Date? {
        guard let uid, let projectID else { return nil }
        let key = storageKey(uid: uid, projectID: projectID, rootTaskID: rootTaskID)
        let interval = defaults.double(forKey: key)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSinceReferenceDate: interval)
    }

    public static func markSeen(
        uid: String?,
        projectID: UUID?,
        rootTaskID: UUID,
        lastSeenAt: Date?,
        defaults: UserDefaults = AppLanguageStore.defaults()
    ) {
        guard let uid, let projectID, let lastSeenAt else { return }
        let key = storageKey(uid: uid, projectID: projectID, rootTaskID: rootTaskID)
        defaults.set(lastSeenAt.timeIntervalSinceReferenceDate, forKey: key)
    }

    /// Removes account-scoped collaboration seen state after account deletion.
    public static func clearAll(for uid: String? = nil, defaults: UserDefaults = AppLanguageStore.defaults()) {
        let prefix: String
        if let uid, !uid.isEmpty {
            prefix = "\(keyPrefix)\(uid)."
        } else {
            prefix = keyPrefix
        }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
