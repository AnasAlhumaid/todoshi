import Foundation
import SwiftData

@Model
public final class TaskItem {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var taskDescription: String
    public var statusRaw: String
    public var priorityRaw: String
    public var dueDate: Date?
    /// When the user wants a local reminder. Distinct from `dueDate`.
    public var reminderDate: Date?
    public var notes: String
    /// Fractional order within the current status (Kanban column) or parent subtask list.
    public var position: Double
    public var completedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    // Recurrence (V4). Existing tasks default to no recurrence.
    public var recurrenceRuleRaw: String?
    public var recurrenceInterval: Int?
    public var recurrenceSeriesID: UUID?
    public var recurrenceGeneration: Int
    /// Successor produced when this occurrence was completed (idempotency).
    public var nextOccurrenceID: UUID?
    /// Predecessor in the same series, if any.
    public var previousOccurrenceID: UUID?

    public var project: Project?

    public var parentTask: TaskItem?

    /// Self-referential children use nullify — deletion of the hierarchy is repository-controlled.
    @Relationship(deleteRule: .nullify, inverse: \TaskItem.parentTask)
    public var subtasks: [TaskItem]?

    @Relationship(deleteRule: .cascade, inverse: \ChecklistItem.task)
    public var checklist: [ChecklistItem]?

    @Relationship(deleteRule: .cascade, inverse: \TaskResource.task)
    public var resources: [TaskResource]?

    @Relationship(inverse: \LabelTag.tasks)
    public var labels: [LabelTag]?

    public var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }

    public var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    public var isRoot: Bool {
        parentTask == nil
    }

    public var recurrenceRule: TaskRecurrenceRule? {
        get { TaskRecurrencePolicy.parse(ruleRaw: recurrenceRuleRaw, interval: recurrenceInterval) }
        set {
            let encoded = TaskRecurrencePolicy.encode(newValue)
            recurrenceRuleRaw = encoded.ruleRaw
            recurrenceInterval = encoded.interval
        }
    }

    public var isRecurring: Bool {
        recurrenceRule != nil
    }

    public init(
        id: UUID = UUID(),
        title: String,
        taskDescription: String = "",
        status: TaskStatus = .todo,
        priority: TaskPriority = .none,
        dueDate: Date? = nil,
        reminderDate: Date? = nil,
        notes: String = "",
        position: Double = FractionalPosition.initial(),
        completedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        project: Project? = nil,
        parentTask: TaskItem? = nil,
        recurrenceRuleRaw: String? = nil,
        recurrenceInterval: Int? = nil,
        recurrenceSeriesID: UUID? = nil,
        recurrenceGeneration: Int = 0,
        nextOccurrenceID: UUID? = nil,
        previousOccurrenceID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.taskDescription = taskDescription
        self.statusRaw = status.rawValue
        self.priorityRaw = priority.rawValue
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.notes = notes
        self.position = position
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.project = project
        self.parentTask = parentTask
        self.recurrenceRuleRaw = recurrenceRuleRaw
        self.recurrenceInterval = recurrenceInterval
        self.recurrenceSeriesID = recurrenceSeriesID
        self.recurrenceGeneration = recurrenceGeneration
        self.nextOccurrenceID = nextOccurrenceID
        self.previousOccurrenceID = previousOccurrenceID
        self.subtasks = []
        self.checklist = []
        self.resources = []
        self.labels = []
    }

    /// Applies status transition rules for `completedAt` and bumps `updatedAt`.
    public func applyStatus(_ newStatus: TaskStatus, at date: Date = .now) {
        status = newStatus
        var stamp = completedAt
        TaskStatusTransitions.apply(newStatus, to: &stamp, at: date)
        completedAt = stamp
        updatedAt = date
    }
}
