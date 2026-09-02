import Foundation

/// Immutable request used to schedule a task reminder (never live SwiftData models).
public struct TaskReminderRequest: Hashable, Sendable {
    public let taskID: UUID
    public let taskTitle: String
    public let projectName: String
    public let reminderDate: Date
    public let dueDate: Date?

    public init(
        taskID: UUID,
        taskTitle: String,
        projectName: String,
        reminderDate: Date,
        dueDate: Date? = nil
    ) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.projectName = projectName
        self.reminderDate = reminderDate
        self.dueDate = dueDate
    }

    public var identifier: String {
        NotificationIdentifier.taskReminder(taskID: taskID)
    }
}

/// Pure decision for whether a reminder should be scheduled or cancelled.
public enum NotificationSchedulingDecision: Equatable, Sendable {
    case schedule(TaskReminderRequest)
    case cancel(taskID: UUID)
    case ignore
}

/// Input snapshot for pure reminder policy (no SwiftData).
public struct TaskReminderInput: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let status: TaskStatus
    public let dueDate: Date?
    public let reminderDate: Date?
    public let isRoot: Bool
    public let projectID: UUID?
    public let projectName: String?
    public let projectIsActive: Bool

    public init(
        id: UUID,
        title: String,
        status: TaskStatus,
        dueDate: Date? = nil,
        reminderDate: Date? = nil,
        isRoot: Bool = true,
        projectID: UUID?,
        projectName: String?,
        projectIsActive: Bool
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.isRoot = isRoot
        self.projectID = projectID
        self.projectName = projectName
        self.projectIsActive = projectIsActive
    }
}

/// Pure scheduling rules for task reminders.
public enum TaskReminderPolicy: Sendable {
    /// MVP: subtasks are full tasks and may schedule local reminders.
    public static let allowsSubtaskReminders = true

    public static func decision(
        for task: TaskReminderInput,
        now: Date = .now
    ) -> NotificationSchedulingDecision {
        guard let reminderDate = task.reminderDate else {
            return .cancel(taskID: task.id)
        }

        guard task.status != .done else {
            return .cancel(taskID: task.id)
        }

        guard task.projectID != nil, task.projectIsActive else {
            return .cancel(taskID: task.id)
        }

        if !allowsSubtaskReminders, !task.isRoot {
            return .cancel(taskID: task.id)
        }

        guard reminderDate > now else {
            return .cancel(taskID: task.id)
        }

        let request = TaskReminderRequest(
            taskID: task.id,
            taskTitle: task.title,
            projectName: task.projectName ?? NexusL10n.tr("common.project"),
            reminderDate: reminderDate,
            dueDate: task.dueDate
        )
        return .schedule(request)
    }

    public static func expectedRequests(
        tasks: [TaskReminderInput],
        now: Date = .now
    ) -> [TaskReminderRequest] {
        tasks.compactMap { task in
            if case .schedule(let request) = decision(for: task, now: now) {
                return request
            }
            return nil
        }
    }

    public static func expectedIdentifiers(
        tasks: [TaskReminderInput],
        now: Date = .now
    ) -> Set<String> {
        Set(expectedRequests(tasks: tasks, now: now).map(\.identifier))
    }
}
