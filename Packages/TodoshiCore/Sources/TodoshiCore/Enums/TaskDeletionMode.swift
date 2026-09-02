import Foundation

/// Explicit strategy when removing a task that may have descendants.
public enum TaskDeletionMode: Sendable {
    /// Delete the task and every descendant (MVP default after user confirmation).
    case deleteDescendants
    /// Promote direct children to root tasks in the same project, then delete the parent only.
    case promoteChildren
}
