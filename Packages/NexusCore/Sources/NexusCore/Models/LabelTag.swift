import Foundation
import SwiftData

@Model
public final class LabelTag {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var colorHex: String
    public var createdAt: Date
    public var updatedAt: Date

    /// Inverse of `TaskItem.labels` (declared on the task side).
    public var tasks: [TaskItem]?

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#8E8E93",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tasks = []
    }
}
