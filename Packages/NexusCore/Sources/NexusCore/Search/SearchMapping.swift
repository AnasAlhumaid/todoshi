import Foundation
import SwiftData

@MainActor
public enum SearchMapping {
    public static func project(_ project: Project) -> SearchableProject {
        let roots = (project.tasks ?? []).filter(\.isRoot)
        return SearchableProject(
            id: project.id,
            name: project.name,
            projectDescription: project.projectDescription,
            icon: project.icon,
            colorHex: project.colorHex,
            position: project.position,
            isArchived: project.status == .archived,
            openRootCount: ProjectTaskCounts.openRootCount(tasks: project.tasks ?? []),
            totalRootCount: roots.count
        )
    }

    public static func task(_ task: TaskItem) -> SearchableTask? {
        guard let project = task.project else { return nil }
        let labelModels = (task.labels ?? [])
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let searchableLabels = labelModels.map {
            SearchableLabel(id: $0.id, name: $0.name, colorHex: $0.colorHex)
        }
        return SearchableTask(
            id: task.id,
            title: task.title,
            taskDescription: task.taskDescription,
            notes: task.notes,
            status: task.status,
            priority: task.priority,
            dueDate: task.dueDate,
            updatedAt: task.updatedAt,
            isRoot: task.isRoot,
            projectID: project.id,
            projectName: project.name,
            projectIcon: project.icon,
            projectColorHex: project.colorHex,
            projectIsArchived: project.status == .archived,
            labels: searchableLabels
        )
    }

    public static func snapshot(
        projects: [Project],
        query: String,
        includeArchived: Bool,
        locale: Locale = .current,
        projectPreviewLimit: Int = SearchBuilder.defaultProjectPreviewLimit,
        taskPreviewLimit: Int = SearchBuilder.defaultTaskPreviewLimit
    ) -> SearchSnapshot {
        let projectInputs = projects.map(project)
        let taskInputs = projects
            .flatMap { $0.tasks ?? [] }
            .compactMap(task)
        return SearchBuilder.build(
            query: query,
            projects: projectInputs,
            tasks: taskInputs,
            includeArchived: includeArchived,
            locale: locale,
            projectPreviewLimit: projectPreviewLimit,
            taskPreviewLimit: taskPreviewLimit
        )
    }
}
