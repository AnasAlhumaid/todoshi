import Foundation
import SwiftData

@MainActor
public enum ProjectBoardMapping {
    /// - Parameters:
    ///   - assigneeNames: membership display names keyed by UID; empty for personal projects.
    ///   - filter: responsibility filter (never a permission filter).
    ///   - viewerUID: current authenticated Firebase UID backing `My Tasks`.
    public static func snapshot(
        from project: Project,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now,
        assigneeNames: [String: String] = [:],
        filter: TaskAssignmentFilter = .all,
        viewerUID: String? = nil
    ) -> ProjectBoardSnapshot {
        let roots = (project.tasks ?? [])
            .filter { $0.isRoot && $0.deletedAt == nil }
            .filter { filter.includes(task: $0, viewerUID: viewerUID) }
        let sections = ProjectBoardSnapshot.workflowStatusOrder.map { status in
            let tasks = roots
                .filter { $0.status == status }
                .map { task in
                    HomeMapping.taskSummary(
                        from: task,
                        projectID: project.id,
                        isShared: project.isShared,
                        viewerUID: viewerUID,
                        calendar: calendar,
                        now: now,
                        assigneeDisplayName: task.assigneeUID.flatMap { assigneeNames[$0] }
                    )
                }
            return ProjectBoardSection(
                status: status,
                tasks: ProjectBoardTaskOrdering.sort(tasks)
            )
        }
        return ProjectBoardSnapshot(projectID: project.id, sections: sections)
    }
}
