import Foundation
import SwiftData

@MainActor
public enum CalendarMapping {
    public static func taskSource(from task: TaskItem) -> CalendarTaskSource? {
        guard let project = task.project else { return nil }
        let checklist = task.checklist ?? []
        let checklistCompleted = checklist.filter(\.isCompleted).count
        let subtasks = task.subtasks ?? []
        let subtaskCompleted = subtasks.filter { $0.status == .done }.count
        return CalendarTaskSource(
            id: task.id,
            title: task.title,
            status: task.status,
            priority: task.priority,
            dueDate: task.dueDate,
            completedAt: task.completedAt,
            updatedAt: task.updatedAt,
            position: task.position,
            isRoot: task.isRoot,
            isRecurring: task.isRecurring,
            projectID: project.id,
            projectName: project.name,
            projectIcon: project.icon,
            projectColorHex: project.colorHex,
            projectIsActive: project.status == .active,
            checklistCompleted: checklistCompleted,
            checklistTotal: checklist.count,
            subtaskCompleted: subtaskCompleted,
            subtaskTotal: subtasks.count
        )
    }

    public static func taskSources(projects: [Project]) -> [CalendarTaskSource] {
        projects
            .flatMap { $0.tasks ?? [] }
            .compactMap(taskSource(from:))
    }
}
