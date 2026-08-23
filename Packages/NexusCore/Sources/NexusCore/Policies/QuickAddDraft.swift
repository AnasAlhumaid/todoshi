import Foundation

/// Quick Add draft — requires project selection for MVP (every task belongs to a project).
public struct QuickAddDraft: Equatable, Sendable {
    public var title: String
    public var projectID: UUID?
    public var status: TaskStatus
    public var priority: TaskPriority
    public var dueDate: Date?
    public var hasDueDate: Bool
    public var taskDescription: String
    public var notes: String
    public var showsOptionalFields: Bool

    public init(
        title: String = "",
        projectID: UUID? = nil,
        status: TaskStatus = .todo,
        priority: TaskPriority = .none,
        dueDate: Date? = nil,
        hasDueDate: Bool = false,
        taskDescription: String = "",
        notes: String = "",
        showsOptionalFields: Bool = false
    ) {
        self.title = title
        self.projectID = projectID
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.hasDueDate = hasDueDate
        self.taskDescription = taskDescription
        self.notes = notes
        self.showsOptionalFields = showsOptionalFields
    }

    public var isValid: Bool {
        FieldValidation.isValidRequiredName(title) && projectID != nil
    }

    public var resolvedDueDate: Date? {
        hasDueDate ? dueDate : nil
    }
}

public enum QuickAddPreferences: Sendable {
    public static let lastProjectIDKey = "nexus.quickAdd.lastProjectID"
    public static let showsOptionalFieldsKey = "nexus.quickAdd.showsOptionalFields"

    /// Returns the stored UUID only when it is still active.
    public static func resolvedProjectID(
        stored: String?,
        activeProjectIDs: Set<UUID>
    ) -> UUID? {
        guard let stored, let id = UUID(uuidString: stored) else { return nil }
        return activeProjectIDs.contains(id) ? id : nil
    }

    public static func storageValue(for projectID: UUID?) -> String? {
        projectID?.uuidString
    }
}
