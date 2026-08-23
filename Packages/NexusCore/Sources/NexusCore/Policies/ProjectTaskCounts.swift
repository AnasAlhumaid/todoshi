import Foundation

/// Pure helpers for project list badges.
public enum ProjectTaskCounts: Sendable {
    /// Root tasks whose status is not `.done`.
    public static func openRootCount(tasks: [TaskItem]) -> Int {
        tasks.filter { $0.isRoot && $0.status != .done }.count
    }

    public static func rootCount(tasks: [TaskItem], status: TaskStatus) -> Int {
        tasks.filter { $0.isRoot && $0.status == status }.count
    }

    public static func totalRootCount(tasks: [TaskItem]) -> Int {
        tasks.filter(\.isRoot).count
    }
}
