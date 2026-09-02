import Foundation

/// Stable presentation context for creating a subtask from Task Detail.
public struct TaskSubtaskFormContext: Identifiable, Equatable, Sendable {
    public let parentTaskID: UUID
    public let projectID: UUID

    public init(parentTaskID: UUID, projectID: UUID) {
        self.parentTaskID = parentTaskID
        self.projectID = projectID
    }

    public var id: String { "subtask-\(parentTaskID.uuidString)" }
}
