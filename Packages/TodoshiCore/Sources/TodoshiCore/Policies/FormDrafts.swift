import Foundation

/// Lightweight draft models + validation for form ViewModels (testable without SwiftUI).
public struct ProjectDraft: Equatable {
    public var name: String
    public var icon: String
    public var colorHex: String
    public var projectDescription: String

    public init(
        name: String = "",
        icon: String = ProjectIconCatalog.defaultSymbol,
        colorHex: String = ProjectColorCatalog.defaultHex,
        projectDescription: String = ""
    ) {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.projectDescription = projectDescription
    }

    public init(project: Project) {
        self.name = project.name
        self.icon = project.icon
        self.colorHex = project.colorHex
        self.projectDescription = project.projectDescription
    }

    public var isValid: Bool {
        FieldValidation.isValidRequiredName(name)
    }
}

public struct TaskDraft: Equatable {
    public var title: String
    public var taskDescription: String
    public var status: TaskStatus
    public var priority: TaskPriority
    public var dueDate: Date?
    public var hasDueDate: Bool
    public var hasReminder: Bool
    public var reminderDate: Date?
    public var notes: String
    public var labelIDs: Set<UUID>
    /// Checklist edits stay in-memory until Save; never holds live `ChecklistItem` models.
    public var checklistItems: [ChecklistItemDraft]
    /// When set on create, task is saved as a subtask of this parent (same project).
    public var parentTaskID: UUID?
    /// Resource drafts — no live SwiftData models.
    public var resources: [TaskResourceDraft]
    /// Root tasks only. Nil means does not repeat.
    public var recurrenceEnabled: Bool
    public var recurrenceKind: TaskRecurrenceKind
    public var recurrenceInterval: Int

    public init(
        title: String = "",
        taskDescription: String = "",
        status: TaskStatus = .todo,
        priority: TaskPriority = .none,
        dueDate: Date? = nil,
        hasDueDate: Bool = false,
        hasReminder: Bool = false,
        reminderDate: Date? = nil,
        notes: String = "",
        labelIDs: Set<UUID> = [],
        checklistItems: [ChecklistItemDraft] = [],
        parentTaskID: UUID? = nil,
        resources: [TaskResourceDraft] = [],
        recurrenceEnabled: Bool = false,
        recurrenceKind: TaskRecurrenceKind = .weekly,
        recurrenceInterval: Int = 1
    ) {
        self.title = title
        self.taskDescription = taskDescription
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.hasDueDate = hasDueDate
        self.hasReminder = hasReminder
        self.reminderDate = reminderDate
        self.notes = notes
        self.labelIDs = labelIDs
        self.checklistItems = checklistItems
        self.parentTaskID = parentTaskID
        self.resources = resources
        self.recurrenceEnabled = recurrenceEnabled
        self.recurrenceKind = recurrenceKind
        self.recurrenceInterval = recurrenceInterval
    }

    public init(task: TaskItem) {
        self.title = task.title
        self.taskDescription = task.taskDescription
        self.status = task.status
        self.priority = task.priority
        self.dueDate = task.dueDate
        self.hasDueDate = task.dueDate != nil
        self.hasReminder = task.reminderDate != nil
        self.reminderDate = task.reminderDate
        self.notes = task.notes
        self.labelIDs = Set((task.labels ?? []).map(\.id))
        self.checklistItems = ChecklistDraftBuilder.drafts(from: task.checklist ?? [])
        self.parentTaskID = task.parentTask?.id
        self.resources = TaskResourceDraftBuilder.drafts(from: task.resources ?? [])
        if let rule = task.recurrenceRule {
            self.recurrenceEnabled = true
            self.recurrenceKind = rule.kind
            self.recurrenceInterval = rule.interval
        } else {
            self.recurrenceEnabled = false
            self.recurrenceKind = .weekly
            self.recurrenceInterval = 1
        }
    }

    public var isValid: Bool {
        FieldValidation.isValidRequiredName(title)
            && checklistDraftsAreValid
            && resourceDraftsAreValid
            && recurrenceValidationIssue == nil
    }

    /// Empty rows are discarded on save; non-empty invalid titles block save.
    public var checklistDraftsAreValid: Bool {
        checklistItems.allSatisfy { item in
            let cleaned = ChecklistValidation.normalizeTitle(item.title)
            if cleaned.isEmpty { return true }
            return ChecklistValidation.issue(title: item.title) == nil
        }
    }

    public var resourceDraftsAreValid: Bool {
        resources.allSatisfy(\.isValid)
    }

    public var resolvedDueDate: Date? {
        hasDueDate ? dueDate : nil
    }

    public var resolvedReminderDate: Date? {
        hasReminder ? reminderDate : nil
    }

    public var isSubtaskDraft: Bool {
        parentTaskID != nil
    }

    public var resolvedRecurrenceRule: TaskRecurrenceRule? {
        guard recurrenceEnabled, !isSubtaskDraft else { return nil }
        return TaskRecurrenceRule(kind: recurrenceKind, interval: recurrenceInterval)
    }

    public var recurrenceSummary: String {
        guard let rule = resolvedRecurrenceRule else {
            return TaskRecurrenceStrings.doesNotRepeat
        }
        return rule.summary
    }

    public var recurrenceValidationIssue: TaskRecurrenceValidationIssue? {
        TaskRecurrencePolicy.validationIssue(
            rule: resolvedRecurrenceRule,
            dueDate: resolvedDueDate,
            isRoot: !isSubtaskDraft
        )
    }

    public mutating func setRecurrenceEnabled(_ enabled: Bool) {
        recurrenceEnabled = enabled
        if !enabled {
            return
        }
        if !recurrenceKind.usesCustomInterval {
            recurrenceInterval = 1
        } else {
            recurrenceInterval = max(1, min(TaskRecurrencePolicy.maxInterval, recurrenceInterval))
        }
    }

    public mutating func enableReminder(
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        hasReminder = true
        if reminderDate == nil || (reminderDate ?? .distantPast) <= now {
            reminderDate = TaskReminderValidation.defaultReminderDate(
                dueDate: resolvedDueDate,
                now: now,
                calendar: calendar
            )
        }
    }

    public mutating func disableReminder() {
        hasReminder = false
        reminderDate = nil
    }

    public func reminderValidationIssue(now: Date = .now) -> TaskReminderValidation.Issue? {
        TaskReminderValidation.issue(
            hasReminder: hasReminder,
            reminderDate: reminderDate,
            status: status,
            now: now
        )
    }

    /// Drops IDs that no longer exist in the catalog.
    public mutating func pruneMissingLabels(validIDs: Set<UUID>) {
        labelIDs = labelIDs.intersection(validIDs)
    }
}
