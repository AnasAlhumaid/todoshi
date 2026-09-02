import Foundation
import SwiftData

@Model
public final class ChecklistItem {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var isCompleted: Bool
    public var position: Double
    public var createdAt: Date
    public var updatedAt: Date

    public var task: TaskItem?

    public init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        position: Double = FractionalPosition.initial(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        task: TaskItem? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.task = task
    }
}
