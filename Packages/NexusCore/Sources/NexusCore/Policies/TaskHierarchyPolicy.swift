import Foundation

/// Pure two-level hierarchy rules for `TaskItem` parent-child relationships.
public enum TaskHierarchyValidationResult: Equatable, Sendable {
    case valid
    case parentNotFound
    case parentIsAlreadySubtask
    case projectMismatch
    case selfParenting
    case cycleDetected
    /// A subtask cannot gain children; a root with children cannot become a subtask (would exceed depth 2).
    case nestedHierarchyNotAllowed
    case missingChild
}

public enum TaskHierarchyPolicy: Sendable {
    /// Maximum depth for MVP: root → direct child only.
    public static let maximumDepth = 2

    /// Validates attaching `child` under `parent` (or creating a child of `parent`).
    public static func validateAttach(
        childID: UUID,
        parentID: UUID,
        parentExists: Bool,
        parentIsRoot: Bool,
        childExists: Bool = true,
        childHasChildren: Bool = false,
        childProjectID: UUID?,
        parentProjectID: UUID?,
        /// True when `parent` appears in `child`'s descendant set (or identical lineage would cycle).
        parentIsDescendantOfChild: Bool = false
    ) -> TaskHierarchyValidationResult {
        if childID == parentID {
            return .selfParenting
        }
        if !parentExists {
            return .parentNotFound
        }
        if !childExists {
            return .missingChild
        }
        if !parentIsRoot {
            return .parentIsAlreadySubtask
        }
        if childHasChildren {
            return .nestedHierarchyNotAllowed
        }
        if parentIsDescendantOfChild {
            return .cycleDetected
        }
        guard let childProjectID, let parentProjectID else {
            return .projectMismatch
        }
        if childProjectID != parentProjectID {
            return .projectMismatch
        }
        return .valid
    }

    /// Whether a task may create new subtasks.
    public static func canAddSubtasks(isRoot: Bool) -> Bool {
        isRoot
    }

    public static func orderedSubtasks(
        _ items: [TaskItem]
    ) -> [TaskItem] {
        items.sorted { lhs, rhs in
            if lhs.position != rhs.position {
                return lhs.position < rhs.position
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

/// Subtask completion stats (`status == .done`). Independent of checklist progress and parent Done.
public struct SubtaskProgress: Hashable, Sendable {
    public let completed: Int
    public let total: Int

    public init(completed: Int, total: Int) {
        self.completed = max(0, completed)
        self.total = max(0, total)
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    public var isComplete: Bool {
        total > 0 && completed >= total
    }

    public var hasProgress: Bool {
        total > 0
    }

    public var compactLabel: String {
        "\(completed)/\(total)"
    }

    public var accessibilityLabel: String {
        SubtaskStrings.progress(completed: completed, total: total)
    }

    public static func from(statuses: [TaskStatus]) -> SubtaskProgress {
        let total = statuses.count
        let completed = statuses.filter { $0 == .done }.count
        return SubtaskProgress(completed: completed, total: total)
    }

    public static func from(tasks: [TaskItem]) -> SubtaskProgress {
        from(statuses: tasks.map(\.status))
    }
}
