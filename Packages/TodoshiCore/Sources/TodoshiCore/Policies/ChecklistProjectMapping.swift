import Foundation
import SwiftData

/// Local presentation helpers for Checklist Project Detail (root TaskItems only).
@MainActor
public enum ChecklistProjectMapping {
    public struct Snapshot: Equatable {
        public let projectID: UUID
        public let remainingCount: Int
        public let inProgressCount: Int
        public let completedCount: Int
        public let activeItems: [TaskItem]
        public let completedItems: [TaskItem]

        public var isEmpty: Bool { activeItems.isEmpty && completedItems.isEmpty }
    }

    /// Manual `position` order within groups; completed items are listed separately at the bottom.
    public static func snapshot(
        from project: Project,
        filter: TaskAssignmentFilter = .all,
        viewerUID: String? = nil
    ) -> Snapshot {
        let roots = (project.tasks ?? [])
            .filter { $0.isRoot && $0.deletedAt == nil }
            .filter { filter.includes(task: $0, viewerUID: viewerUID) }
            .sorted { lhs, rhs in
                if lhs.position != rhs.position { return lhs.position < rhs.position }
                return lhs.createdAt < rhs.createdAt
            }

        let active = roots.filter { $0.status != .done }
            .sorted { lhs, rhs in
                // Prefer In Progress above Not Started while preserving position within each band.
                let lhsRank = checklistBand(lhs.status)
                let rhsRank = checklistBand(rhs.status)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                if lhs.position != rhs.position { return lhs.position < rhs.position }
                return lhs.createdAt < rhs.createdAt
            }
        let completed = roots.filter { $0.status == .done }

        return Snapshot(
            projectID: project.id,
            remainingCount: roots.filter { $0.status == .todo }.count,
            inProgressCount: roots.filter { $0.status == .inProgress }.count,
            completedCount: completed.count,
            activeItems: active,
            completedItems: completed
        )
    }

    private static func checklistBand(_ status: TaskStatus) -> Int {
        switch status {
        case .inProgress: return 0
        case .todo, .backlog, .review: return 1
        case .done: return 2
        }
    }
}
