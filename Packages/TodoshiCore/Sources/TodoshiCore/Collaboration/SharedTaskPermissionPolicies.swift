import Foundation

/// Task collaboration access for project members (separate from `ProjectMemberRole`).
public enum ProjectMemberAccessLevel: String, Codable, Sendable, CaseIterable, Equatable {
    case full
    case restricted

    /// Legacy memberships without `accessLevel` behave as full task editors.
    public static let legacyDefault: ProjectMemberAccessLevel = .full

    /// New invite acceptances default to selected-tasks-only.
    public static let inviteDefault: ProjectMemberAccessLevel = .restricted

    public static func resolved(raw: String?) -> ProjectMemberAccessLevel {
        guard let raw, let value = ProjectMemberAccessLevel(rawValue: raw) else {
            return legacyDefault
        }
        return value
    }
}

/// Who may mutate shared task content (not comments, not project admin).
public enum SharedTaskEditAuthorization: Sendable {
    public static func canEditTaskContent(
        role: ProjectMemberRole?,
        accessLevel: ProjectMemberAccessLevel?,
        viewerUID: String?,
        rootEditorUIDs: [String]
    ) -> Bool {
        guard let role, let viewerUID, !viewerUID.isEmpty else { return false }
        if role == .owner { return true }
        guard role == .member else { return false }
        let level = accessLevel ?? ProjectMemberAccessLevel.legacyDefault
        switch level {
        case .full:
            return true
        case .restricted:
            return rootEditorUIDs.contains(viewerUID)
        }
    }

    public static func canCreateRootTask(
        role: ProjectMemberRole?,
        accessLevel: ProjectMemberAccessLevel?
    ) -> Bool {
        guard let role else { return false }
        if role == .owner { return true }
        guard role == .member else { return false }
        return (accessLevel ?? .legacyDefault) == .full
    }

    public static func canCreateSubtask(
        role: ProjectMemberRole?,
        accessLevel: ProjectMemberAccessLevel?,
        viewerUID: String?,
        rootEditorUIDs: [String]
    ) -> Bool {
        canEditTaskContent(
            role: role,
            accessLevel: accessLevel,
            viewerUID: viewerUID,
            rootEditorUIDs: rootEditorUIDs
        )
    }

    public static func canManageAccessLevels(role: ProjectMemberRole?) -> Bool {
        role == .owner
    }

    public static func canManageTaskEditorUIDs(role: ProjectMemberRole?) -> Bool {
        role == .owner
    }

    public static func canMutateProjectLabels(
        role: ProjectMemberRole?,
        accessLevel: ProjectMemberAccessLevel?
    ) -> Bool {
        guard let role else { return false }
        if role == .owner { return true }
        return role == .member && (accessLevel ?? .legacyDefault) == .full
    }

    /// Comments stay independent of task edit ACL (Phase 5).
    public static func canCommentIndependentlyOfTaskEdit() -> Bool { true }
}

/// Resolves the root task whose `editorUIDs` authorize a task or its subtask.
public enum SharedTaskEditorInheritance: Sendable {
    public static func rootTaskID(for task: TaskItem) -> UUID {
        task.parentTask?.id ?? task.id
    }

    public static func editorUIDs(for task: TaskItem) -> [String] {
        let root = task.parentTask ?? task
        return root.editorUIDs ?? []
    }

    public static func withEditor(
        _ uids: [String],
        including uid: String,
        enabled: Bool
    ) -> [String] {
        var set = Set(uids.filter { !$0.isEmpty })
        if enabled {
            set.insert(uid)
        } else {
            set.remove(uid)
        }
        return set.sorted()
    }
}

public enum SharedTaskPermissionPresentation: Sendable {
    public static var sectionTitle: String { TodoshiL10n.tr("project.permissions.taskAccess") }
    public static var fullAccess: String { TodoshiL10n.tr("project.permissions.fullAccess") }
    public static var selectedTasksOnly: String { TodoshiL10n.tr("project.permissions.selectedTasksOnly") }
    public static var fullAccessHint: String { TodoshiL10n.tr("project.permissions.fullAccessHint") }
    public static var selectedHint: String { TodoshiL10n.tr("project.permissions.selectedHint") }
    public static var allowedTasks: String { TodoshiL10n.tr("project.permissions.allowedTasks") }
    public static var taskPermissions: String { TodoshiL10n.tr("task.permissions.title") }
    public static var readOnly: String { TodoshiL10n.tr("task.permissions.readOnly") }
    public static var noEditPermission: String { TodoshiL10n.tr("task.permissions.noEdit") }
    public static var permissionRevoked: String { TodoshiL10n.tr("task.permissions.revoked") }
    public static var alwaysOwner: String { TodoshiL10n.tr("task.permissions.alwaysOwner") }
    public static var hasFullAccess: String { TodoshiL10n.tr("task.permissions.hasFullAccess") }
}

/// Phase 6.1 — when a denied task-content action should surface toast feedback.
public enum SharedTaskPermissionFeedback: Sendable, Equatable {
    case none
    /// Restricted member attempted a task-content mutation.
    case deniedEdit(ProjectType)
    /// Cloud write rejected after remote ACL revocation.
    case revoked

    public var toastMessage: String? {
        switch self {
        case .none: return nil
        case .deniedEdit(let type):
            return ProjectTerminologyPolicy.noEditPermission(for: type)
        case .revoked: return SharedTaskPermissionPresentation.permissionRevoked
        }
    }

    /// Intercept a task-content mutation attempt.
    public static func forEditAttempt(
        canEditTaskContent: Bool,
        projectType: ProjectType = .tasks
    ) -> SharedTaskPermissionFeedback {
        canEditTaskContent ? .none : .deniedEdit(projectType)
    }

    /// Runtime permission-denied after Owner revoke.
    public static func forPermissionDeniedWrite() -> SharedTaskPermissionFeedback { .revoked }

    /// Comments stay collaborative and must never request this toast.
    public static func forCommentAction() -> SharedTaskPermissionFeedback { .none }

    public var shouldShowToast: Bool { self != .none }
}

/// Auto-dismiss timing for lightweight Todoshi toasts (no global notification framework).
public enum TodoshiToastPolicy: Sendable {
    public static let defaultVisibleDuration: TimeInterval = 2.5

    /// Returns `true` when a later generation should clear the current toast.
    public static func shouldClear(
        activeGeneration: UInt64,
        clearingGeneration: UInt64
    ) -> Bool {
        activeGeneration == clearingGeneration
    }
}

/// Local pre-check before optimistic shared mutations for restricted members.
public enum SharedTaskPermissionGate: Sendable {
    public static func shouldBlockLocalMutation(
        isShared: Bool,
        role: ProjectMemberRole?,
        accessLevel: ProjectMemberAccessLevel?,
        viewerUID: String?,
        rootEditorUIDs: [String]
    ) -> Bool {
        guard isShared else { return false }
        return !SharedTaskEditAuthorization.canEditTaskContent(
            role: role,
            accessLevel: accessLevel,
            viewerUID: viewerUID,
            rootEditorUIDs: rootEditorUIDs
        )
    }
}

/// Posted when a shared task cloud write is denied so UI can show a non-destructive message.
public enum SharedTaskPermissionDeniedCenter {
    public static let notification = Notification.Name("com.anashamad.Todoshi.sharedTaskPermissionDenied")
    public static let taskIDKey = "taskID"
    public static let projectIDKey = "projectID"

    public static func post(projectID: UUID, taskID: UUID) {
        NotificationCenter.default.post(
            name: notification,
            object: nil,
            userInfo: [
                projectIDKey: projectID.uuidString,
                taskIDKey: taskID.uuidString,
            ]
        )
    }
}
