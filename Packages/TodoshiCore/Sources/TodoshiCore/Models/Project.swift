import Foundation
import SwiftData

@Model
public final class Project {
    @Attribute(.unique) public var id: UUID
    public var name: String
    /// SF Symbol name.
    public var icon: String
    public var colorHex: String
    public var projectDescription: String
    public var statusRaw: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Fractional list order among peers.
    public var position: Double

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.project)
    public var tasks: [TaskItem]?

    public var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "folder.fill",
        colorHex: String = "#5B8DEF",
        projectDescription: String = "",
        status: ProjectStatus = .active,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        position: Double = FractionalPosition.initial()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.projectDescription = projectDescription
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.position = position
        self.tasks = []
    }
}
