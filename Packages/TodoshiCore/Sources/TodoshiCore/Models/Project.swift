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

    /// Collaboration Phase 2 — `personal` / `shared`. Optional for additive V5 open of existing stores.
    public var sharingModeRaw: String?
    /// Firestore document ID when shared; equals `id.uuidString`.
    public var remoteProjectID: String?
    public var sharedAt: Date?
    /// Firebase UID whose membership owns this shared local cache (account isolation).
    public var collaborationOwnerUID: String?
    /// True when listeners hit permission-denied; do not convert to personal.
    public var syncUnavailable: Bool?
    /// Phase 8 — `tasks` / `checklist`. Optional for additive V8 open of existing stores.
    public var projectTypeRaw: String?
    /// Custom board columns as JSON (`[ProjectColumn]`). Nil means the three default columns.
    /// Optional so existing stores open non-destructively.
    public var columnsJSON: String?

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.project)
    public var tasks: [TaskItem]?

    public var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    public var sharingMode: ProjectSharingMode {
        get { ProjectSharingMode(rawValue: sharingModeRaw ?? "") ?? .personal }
        set { sharingModeRaw = newValue.rawValue }
    }

    /// Legacy projects without a stored type behave as Tasks.
    public var projectType: ProjectType {
        get { ProjectType.resolve(projectTypeRaw) }
        set { projectTypeRaw = newValue.rawValue }
    }

    public var isShared: Bool { sharingMode == .shared }

    public var isSyncUnavailable: Bool { syncUnavailable == true }

    public var isChecklist: Bool { projectType == .checklist }

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "folder.fill",
        colorHex: String = "#5B8DEF",
        projectDescription: String = "",
        status: ProjectStatus = .active,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        position: Double = FractionalPosition.initial(),
        sharingMode: ProjectSharingMode = .personal,
        remoteProjectID: String? = nil,
        sharedAt: Date? = nil,
        collaborationOwnerUID: String? = nil,
        syncUnavailable: Bool? = nil,
        projectType: ProjectType = .tasks
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
        self.sharingModeRaw = sharingMode.rawValue
        self.remoteProjectID = remoteProjectID
        self.sharedAt = sharedAt
        self.collaborationOwnerUID = collaborationOwnerUID
        self.syncUnavailable = syncUnavailable
        self.projectTypeRaw = projectType.rawValue
        self.tasks = []
    }
}
