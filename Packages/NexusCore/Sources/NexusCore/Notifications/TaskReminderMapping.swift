import Foundation
import SwiftData

@MainActor
public enum TaskReminderMapping {
    public static func input(from task: TaskItem) -> TaskReminderInput {
        let project = task.project
        return TaskReminderInput(
            id: task.id,
            title: task.title,
            status: task.status,
            dueDate: task.dueDate,
            reminderDate: task.reminderDate,
            isRoot: task.isRoot,
            projectID: project?.id,
            projectName: project?.name,
            projectIsActive: project?.status == .active
        )
    }

    public static func loadAll(from context: ModelContext) throws -> [TaskReminderInput] {
        try context.fetch(FetchDescriptor<TaskItem>()).map(input(from:))
    }
}
