import Foundation
import SwiftData

/// Schema V1 — baseline before task reminders (historical reference only).
public enum TodoshiSchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Project.self, TaskItem.self, LabelTag.self, ChecklistItem.self]
    }
}

/// Schema V2 — optional `TaskItem.reminderDate` (historical reference only).
public enum TodoshiSchemaV2: VersionedSchema {
    public static var versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Project.self, TaskItem.self, LabelTag.self, ChecklistItem.self]
    }
}

/// Schema V3 — TaskResource attachments (historical reference only).
public enum TodoshiSchemaV3: VersionedSchema {
    public static var versionIdentifier = Schema.Version(3, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Project.self, TaskItem.self, LabelTag.self, ChecklistItem.self, TaskResource.self]
    }
}

/// Schema V4 — optional recurrence metadata on `TaskItem` (historical reference only).
public enum TodoshiSchemaV4: VersionedSchema {
    public static var versionIdentifier = Schema.Version(4, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Project.self, TaskItem.self, LabelTag.self, ChecklistItem.self, TaskResource.self]
    }
}

/// Schema V5 — Project sharing metadata (historical reference only).
public enum TodoshiSchemaV5: VersionedSchema {
    public static var versionIdentifier = Schema.Version(5, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Project.self, TaskItem.self, LabelTag.self, ChecklistItem.self, TaskResource.self]
    }
}

/// Schema V6 — production schema with shared sync metadata + Phase 6 editorUIDs.
///
/// Sole active versioned schema (avoids SwiftData duplicate version checksums).
/// Additive optionals (`collaborationOwnerUID`, `syncUnavailable`, task `deletedAt` /
/// `remoteUpdatedAt`, `editorUIDs`) open existing stores non-destructively.
public enum TodoshiSchemaV6: VersionedSchema {
    public static var versionIdentifier = Schema.Version(6, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Project.self, TaskItem.self, LabelTag.self, ChecklistItem.self, TaskResource.self]
    }
}

/// Schema V7 — Phase 7 task assignment (`TaskItem.assigneeUID`).
public enum TodoshiSchemaV7: VersionedSchema {
    public static var versionIdentifier = Schema.Version(7, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Project.self, TaskItem.self, LabelTag.self, ChecklistItem.self, TaskResource.self]
    }
}

/// Schema V8 — Phase 8 project types (`Project.projectTypeRaw`) (historical reference only).
public enum TodoshiSchemaV8: VersionedSchema {
    public static var versionIdentifier = Schema.Version(8, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Project.self, TaskItem.self, LabelTag.self, ChecklistItem.self, TaskResource.self]
    }
}

/// Schema V9 — Phase 8.1 checklist completion attribution.
///
/// Sole active versioned schema. `completedByUID` / `completedByDisplayName` are additive
/// optionals so existing stores open non-destructively (legacy completed items stay nil).
public enum TodoshiSchemaV9: VersionedSchema {
    public static var versionIdentifier = Schema.Version(9, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Project.self, TaskItem.self, LabelTag.self, ChecklistItem.self, TaskResource.self]
    }
}

public enum TodoshiSchemaMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [TodoshiSchemaV9.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}

public enum TodoshiSchema {
    public static let currentModels: [any PersistentModel.Type] = TodoshiSchemaV9.models
    public static let currentVersion = TodoshiSchemaV9.versionIdentifier

    public static func makeSchema() -> Schema {
        Schema(currentModels)
    }
}
