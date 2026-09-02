import Foundation

/// Completion metadata rules for status changes.
public enum TaskStatusTransitions: Sendable {
    /// Applies status and updates `completedAt` according to product rules.
    public static func apply(
        _ status: TaskStatus,
        to completedAt: inout Date?,
        at date: Date = .now
    ) {
        if status == .done {
            if completedAt == nil {
                completedAt = date
            }
        } else {
            completedAt = nil
        }
    }
}
