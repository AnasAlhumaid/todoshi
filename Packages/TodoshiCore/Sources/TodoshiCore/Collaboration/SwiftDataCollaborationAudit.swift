import Foundation

/// Design-time audit of current SwiftData entities for future shared-project metadata.
/// Phase 0 does not modify the schema; this documents likely future connection points.
public enum SwiftDataCollaborationAudit: Sendable {
    public static let auditedEntities: [String] = [
        "Project",
        "TaskItem",
        "LabelTag",
        "ChecklistItem",
        "TaskResource"
    ]

    /// Likely future local metadata (not implemented in Phase 0).
    public static let futureLocalMetadataConcepts: [String] = [
        "sharingMode",
        "remoteProjectID",
        "remoteUpdatedAt",
        "syncState"
    ]

    public static let recurrenceRelationshipsAudited = true
    public static let parentSubtaskRelationshipsAudited = true
}
