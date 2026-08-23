import Foundation
import SwiftData

@MainActor
public enum DashboardMapping {
    public static func taskInput(from task: TaskItem) -> DashboardTaskInput? {
        guard let project = task.project else { return nil }
        return DashboardTaskInput(
            id: task.id,
            title: task.title,
            status: task.status,
            priority: task.priority,
            dueDate: task.dueDate,
            completedAt: task.completedAt,
            updatedAt: task.updatedAt,
            position: task.position,
            isRoot: task.isRoot,
            projectID: project.id,
            projectName: project.name,
            projectIcon: project.icon,
            projectColorHex: project.colorHex,
            projectIsActive: project.status == .active
        )
    }

    public static func projectInput(from project: Project) -> DashboardProjectInput {
        let roots = (project.tasks ?? []).filter(\.isRoot)
        let open = ProjectTaskCounts.openRootCount(tasks: project.tasks ?? [])
        return DashboardProjectInput(
            id: project.id,
            name: project.name,
            icon: project.icon,
            colorHex: project.colorHex,
            projectDescription: project.projectDescription,
            position: project.position,
            status: project.status,
            openRootCount: open,
            totalRootCount: roots.count
        )
    }

    public static func snapshot(
        projects: [Project],
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> DashboardSnapshot {
        let projectInputs = projects.map(projectInput(from:))
        let taskInputs = projects
            .flatMap { $0.tasks ?? [] }
            .compactMap(taskInput(from:))
        return DashboardBuilder.build(
            projects: projectInputs,
            tasks: taskInputs,
            calendar: calendar,
            now: now
        )
    }
}
