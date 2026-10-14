import Foundation

/// Membership facts needed to reason about assignment, independent of Firebase types.
public struct AssignmentCandidate: Sendable, Equatable, Identifiable {
    public let uid: String
    public let role: ProjectMemberRole
    public let accessLevel: ProjectMemberAccessLevel?
    public let displayName: String?

    public var id: String { uid }

    public init(
        uid: String,
        role: ProjectMemberRole,
        accessLevel: ProjectMemberAccessLevel? = nil,
        displayName: String? = nil
    ) {
        self.uid = uid
        self.role = role
        self.accessLevel = accessLevel
        self.displayName = displayName
    }

    /// Owner always behaves as full; legacy memberships without a stored level are full.
    public var resolvedAccessLevel: ProjectMemberAccessLevel {
        if role == .owner { return .full }
        return accessLevel ?? ProjectMemberAccessLevel.legacyDefault
    }

    /// Restricted members need an explicit `editorUIDs` entry to act on their assignment.
    public var needsEditorGrant: Bool {
        role != .owner && resolvedAccessLevel == .restricted
    }
}

/// The atomic root-task mutation produced by an assignment change.
public struct TaskAssignmentPlan: Sendable, Equatable {
    public let assigneeUID: String?
    public let editorUIDs: [String]
    /// True when the plan adds an ACL grant so the assignee can act on the task.
    public let grantsEditAccess: Bool

    public init(assigneeUID: String?, editorUIDs: [String], grantsEditAccess: Bool) {
        self.assigneeUID = assigneeUID
        self.editorUIDs = editorUIDs
        self.grantsEditAccess = grantsEditAccess
    }
}

/// Responsibility (`assigneeUID`) rules. Never an authorization source — see `SharedTaskEditAuthorization`.
public enum TaskAssignmentPolicy: Sendable {
    /// Only the project Owner may change assignment.
    public static func canAssign(role: ProjectMemberRole?) -> Bool {
        role == .owner
    }

    /// Assignment is managed on root tasks only; subtasks inherit responsibility.
    public static func canAssign(task: TaskItem) -> Bool {
        task.isRoot
    }

    /// An assignee must be a current member of the same project.
    public static func isValidAssignee(uid: String, members: [AssignmentCandidate]) -> Bool {
        !uid.isEmpty && members.contains { $0.uid == uid }
    }

    /// Editor UIDs required so `candidate` can actually work on the task.
    ///
    /// Returns `nil` when no ACL change is needed (owner, full member, or already granted).
    public static func requiredEditorGrant(
        assigneeMembership candidate: AssignmentCandidate?,
        currentEditorUIDs: [String]
    ) -> [String]? {
        guard let candidate, candidate.needsEditorGrant else { return nil }
        guard !currentEditorUIDs.contains(candidate.uid) else { return nil }
        return SharedTaskEditorInheritance.withEditor(
            currentEditorUIDs,
            including: candidate.uid,
            enabled: true
        )
    }

    /// Single atomic plan for assign / reassign / unassign.
    ///
    /// Unassignment and reassignment never revoke existing editor grants: Todoshi does not
    /// track whether a grant came from assignment or from manual Phase 6 permission management.
    public static func plan(
        assignTo candidate: AssignmentCandidate?,
        currentEditorUIDs: [String]
    ) -> TaskAssignmentPlan {
        let normalizedEditors = Set(currentEditorUIDs.filter { !$0.isEmpty }).sorted()
        guard let candidate else {
            return TaskAssignmentPlan(
                assigneeUID: nil,
                editorUIDs: normalizedEditors,
                grantsEditAccess: false
            )
        }
        if let granted = requiredEditorGrant(
            assigneeMembership: candidate,
            currentEditorUIDs: normalizedEditors
        ) {
            return TaskAssignmentPlan(
                assigneeUID: candidate.uid,
                editorUIDs: granted,
                grantsEditAccess: true
            )
        }
        return TaskAssignmentPlan(
            assigneeUID: candidate.uid,
            editorUIDs: normalizedEditors,
            grantsEditAccess: false
        )
    }

    /// Members may never create pre-assigned root tasks; only Owner can.
    public static func allowsAssignedCreation(role: ProjectMemberRole?) -> Bool {
        role == .owner
    }
}

/// Guards that keep "assigned but read-only" states from being created.
public enum TaskAssignmentIntegrityPolicy: Sendable {
    /// Owner may not strip edit access from the restricted member currently responsible.
    public static func canRemoveEditor(
        uid: String,
        assigneeUID: String?,
        candidate: AssignmentCandidate?
    ) -> Bool {
        guard uid == assigneeUID else { return true }
        guard let candidate else { return true }
        return !candidate.needsEditorGrant
    }

    /// Root tasks that must gain `uid` in `editorUIDs` before demoting them to restricted.
    public static func rootTasksNeedingRepair(
        forDemotedUID uid: String,
        rootTasks: [TaskItem]
    ) -> [TaskItem] {
        rootTasks.filter { task in
            guard task.isRoot, task.deletedAt == nil else { return false }
            guard task.assigneeUID == uid else { return false }
            return !(task.editorUIDs ?? []).contains(uid)
        }
    }

    /// Idempotent editor list for a repaired task.
    public static func repairedEditorUIDs(for task: TaskItem, uid: String) -> [String] {
        SharedTaskEditorInheritance.withEditor(task.editorUIDs ?? [], including: uid, enabled: true)
    }
}

/// Responsibility-based filtering (never permission-based).
public enum TaskAssignmentFilter: String, Sendable, CaseIterable, Identifiable {
    case all
    case mine

    public var id: String { rawValue }

    public var title: String { title(for: .tasks) }

    public func title(for type: ProjectType) -> String {
        switch self {
        case .all: return ProjectTerminologyPolicy.allFilter(type)
        case .mine: return ProjectTerminologyPolicy.mineFilter(type)
        }
    }

    /// `My Tasks` / `My Items` = root tasks whose assignee is the current authenticated UID.
    public func includes(task: TaskItem, viewerUID: String?) -> Bool {
        switch self {
        case .all:
            return true
        case .mine:
            guard let viewerUID, !viewerUID.isEmpty else { return false }
            return task.assigneeUID == viewerUID
        }
    }

    public func apply(to rootTasks: [TaskItem], viewerUID: String?) -> [TaskItem] {
        rootTasks.filter { includes(task: $0, viewerUID: viewerUID) }
    }
}

/// Owner-facing progress derived from live task status (no separate progress field).
public struct MemberAssignmentProgress: Sendable, Equatable {
    public let total: Int
    public let countsByStatus: [TaskStatus: Int]

    public init(total: Int, countsByStatus: [TaskStatus: Int]) {
        self.total = total
        self.countsByStatus = countsByStatus
    }

    public func count(for status: TaskStatus) -> Int {
        countsByStatus[status] ?? 0
    }

    public static let empty = MemberAssignmentProgress(total: 0, countsByStatus: [:])
}

public enum MemberAssignmentProgressPolicy: Sendable {
    /// Live root tasks assigned to `uid`. Soft-deleted tasks are excluded.
    public static func assignedRootTasks(for uid: String, in rootTasks: [TaskItem]) -> [TaskItem] {
        rootTasks
            .filter { $0.isRoot && $0.deletedAt == nil && $0.assigneeUID == uid }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public static func progress(for uid: String, in rootTasks: [TaskItem]) -> MemberAssignmentProgress {
        progress(for: uid, in: rootTasks, projectType: .tasks)
    }

    public static func progress(
        for uid: String,
        in rootTasks: [TaskItem],
        projectType: ProjectType
    ) -> MemberAssignmentProgress {
        let assigned = assignedRootTasks(for: uid, in: rootTasks)
        let allowed = Set(ProjectStatusPolicy.progressStatuses(for: projectType))
        var counts: [TaskStatus: Int] = [:]
        for task in assigned where allowed.contains(task.status) {
            counts[task.status, default: 0] += 1
        }
        let total = counts.values.reduce(0, +)
        return MemberAssignmentProgress(total: total, countsByStatus: counts)
    }
}

public enum TaskAssignmentPresentation: Sendable {
    public static var assigneeSectionTitle: String { TodoshiL10n.tr("task.assignment.sectionTitle") }
    public static var assigneeLabel: String { TodoshiL10n.tr("task.assignment.assignee") }
    public static var unassigned: String { TodoshiL10n.tr("task.assignment.unassigned") }
    public static var assignedTasks: String { TodoshiL10n.tr("task.assignment.assignedTasks") }
    public static var myTasks: String { TodoshiL10n.tr("task.assignment.myTasks") }
    public static var allTasks: String { TodoshiL10n.tr("task.assignment.allTasks") }
    public static var assignTask: String { TodoshiL10n.tr("task.assignment.assign") }
    public static var changeAssignee: String { TodoshiL10n.tr("task.assignment.change") }
    public static var unassign: String { TodoshiL10n.tr("task.assignment.unassignAction") }
    public static var autoGrantFooter: String { TodoshiL10n.tr("task.assignment.autoGrantFooter") }
    public static var assigneeAclGuard: String { TodoshiL10n.tr("task.assignment.aclGuard") }
    public static var totalLabel: String { TodoshiL10n.tr("task.assignment.total") }

    /// Membership `displayName` only — never `/users/{uid}` and never the raw UID.
    public static func memberDisplayName(_ displayName: String?) -> String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return TodoshiL10n.tr("project.members.unnamed")
        }
        return trimmed
    }

    public static func assigneeName(
        for uid: String?,
        members: [AssignmentCandidate]
    ) -> String {
        guard let uid, !uid.isEmpty else { return unassigned }
        guard let member = members.first(where: { $0.uid == uid }) else { return unassigned }
        return memberDisplayName(member.displayName)
    }
}
