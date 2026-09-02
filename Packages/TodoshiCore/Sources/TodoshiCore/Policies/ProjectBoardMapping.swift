import Foundation
import SwiftData

@MainActor
public enum ProjectBoardMapping {
    public static func snapshot(
        from project: Project,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> ProjectBoardSnapshot {
        let roots = (project.tasks ?? []).filter(\.isRoot)
        let sections = ProjectBoardSnapshot.workflowStatusOrder.map { status in
            let tasks = roots
                .filter { $0.status == status }
                .map { HomeMapping.taskSummary(from: $0, projectID: project.id, calendar: calendar, now: now) }
            return ProjectBoardSection(
                status: status,
                tasks: ProjectBoardTaskOrdering.sort(tasks)
            )
        }
        return ProjectBoardSnapshot(projectID: project.id, sections: sections)
    }
}
