import Foundation
import SwiftData

/// Schema V1 — baseline before task reminders (historical reference only).
public enum NexusSchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Project.self, TaskItem.self, LabelTag.self, ChecklistItem.self]
    }
}

/// Schema V2 — optional `TaskItem.reminderDate` (historical reference only).
public enum NexusSchemaV2: VersionedSchema {
    public static var versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Project.self, TaskItem.self, LabelTag.self, ChecklistItem.self]
    }
}

/// Schema V3 — TaskResource attachments (historical reference only).
public enum NexusSchemaV3: VersionedSchema {
    public static var versionIdentifier = Schema.Version(3, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Project.self, TaskItem.self, LabelTag.self, ChecklistItem.self, TaskResource.self]
    }
}

/// Schema V4 — current production schema with optional recurrence metadata on `TaskItem`.
///
/// Sole active versioned schema (avoids SwiftData duplicate version checksums). New optional
/// attributes open existing stores non-destructively; Release never resets the App Group store.
public enum NexusSchemaV4: VersionedSchema {
    public static var versionIdentifier = Schema.Version(4, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Project.self, TaskItem.self, LabelTag.self, ChecklistItem.self, TaskResource.self]
    }
}

public enum NexusSchemaMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [NexusSchemaV4.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}

public enum NexusSchema {
    public static let currentModels: [any PersistentModel.Type] = NexusSchemaV4.models
    public static let currentVersion = NexusSchemaV4.versionIdentifier

    public static func makeSchema() -> Schema {
        Schema(currentModels)
    }
}
