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
    /// Firebase UID of the member who marked this item Done (Phase 8.1). Nil for personal/legacy.
    public var completedByUID: String?
    /// Membership displayName snapshot at completion time (historical; survives member removal).
    public var completedByDisplayName: String?
    public var createdAt: Date
    public var updatedAt: Date
    /// Soft-delete tombstone for shared cloud reconciliation (nil = live).
    public var deletedAt: Date?
    /// Last applied authoritative remote `updatedAt` (shared projects).
    public var remoteUpdatedAt: Date?
    /// Restricted-member editors for this root task (ignored on subtasks; inherit from root).
    public var editorUIDs: [String]?
    /// Member responsible for this root task (Phase 7). Subtasks inherit from their root.
    public var assigneeUID: String?
    /// Latest collaboration activity timestamp on root tasks (shared projects only).
    public var lastActivityAt: Date?
    /// UID of the member who caused the latest activity (not shown in UI).
    public var lastActivityByUID: String?
    /// Kind of latest activity (`TaskCollaborationActivityKind` raw value).
    public var lastActivityKindRaw: String?

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

    /// Board column the task sits in (`ProjectColumn.id`). Nil or stale values fall back to
    /// the first column whose kind matches `status`; see `ProjectColumnsPolicy.column(for:in:)`.
    public var columnIDRaw: String?

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

    /// Responsibility resolved through the root task (subtasks never carry their own assignee).
    public var effectiveAssigneeUID: String? {
        (parentTask ?? self).assigneeUID
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
        completedByUID: String? = nil,
        completedByDisplayName: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        remoteUpdatedAt: Date? = nil,
        editorUIDs: [String]? = nil,
        assigneeUID: String? = nil,
        lastActivityAt: Date? = nil,
        lastActivityByUID: String? = nil,
        lastActivityKindRaw: String? = nil,
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
        self.completedByUID = completedByUID
        self.completedByDisplayName = completedByDisplayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.remoteUpdatedAt = remoteUpdatedAt
        self.editorUIDs = editorUIDs
        self.assigneeUID = assigneeUID
        self.lastActivityAt = lastActivityAt
        self.lastActivityByUID = lastActivityByUID
        self.lastActivityKindRaw = lastActivityKindRaw
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

    /// Applies status transition rules for completion metadata and bumps `updatedAt`.
    public func applyStatus(
        _ newStatus: TaskStatus,
        at date: Date = .now,
        completionActor: TaskCompletionActor? = nil
    ) {
        let previous = status
        status = newStatus
        var stamp = completedAt
        var byUID = completedByUID
        var byName = completedByDisplayName
        TaskCompletionAttribution.apply(
            from: previous,
            to: newStatus,
            completedAt: &stamp,
            completedByUID: &byUID,
            completedByDisplayName: &byName,
            actor: completionActor,
            at: date
        )
        completedAt = stamp
        completedByUID = byUID
        completedByDisplayName = byName
        updatedAt = date
    }
}

extension TaskItem {
    /// False once the model is deleted or detached from its context (e.g. a remote delete
    /// landed while a view still holds it). Attribute reads on such models crash.
    public var isLive: Bool {
        if isDeleted { return false }
        // Never-saved models (no store yet) are plain values and safe to read.
        if persistentModelID.storeIdentifier == nil { return true }
        return modelContext != nil
    }
}
