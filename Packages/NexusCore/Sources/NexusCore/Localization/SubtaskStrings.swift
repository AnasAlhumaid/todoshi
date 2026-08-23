import Foundation

public enum SubtaskStrings: Sendable {
    public static var subtasks: String { NexusL10n.tr("subtasks.title") }
    public static var subtask: String { NexusL10n.tr("subtasks.subtask") }
    public static var addSubtask: String { NexusL10n.tr("subtasks.add") }
    public static var subtaskOf: String { NexusL10n.tr("subtasks.of") }
    public static var promoteToRoot: String { NexusL10n.tr("subtasks.promote") }
    public static var deleteParent: String { NexusL10n.tr("subtasks.deleteParent") }
    public static var deleteAllSubtasks: String { NexusL10n.tr("subtasks.deleteAll") }
    public static var promoteSubtasks: String { NexusL10n.tr("subtasks.promoteAll") }
    public static var completedSubtasks: String { NexusL10n.tr("subtasks.completed") }
    public static var noSubtasks: String { NexusL10n.tr("subtasks.none") }
    public static var cannotAddNested: String { NexusL10n.tr("subtasks.cannotNested") }
    public static var parentTask: String { NexusL10n.tr("subtasks.parent") }
    public static var invalidParent: String { NexusL10n.tr("subtasks.invalidParent") }
    public static var sameProjectRequired: String { NexusL10n.tr("subtasks.sameProject") }
    public static var progressFormat: String { NexusL10n.tr("subtasks.progress") }
    public static var promoteConfirmTitle: String { NexusL10n.tr("subtasks.promoteTitle") }
    public static var promoteConfirmMessage: String { NexusL10n.tr("subtasks.promoteMessage") }
    public static var deleteTaskTitle: String { NexusL10n.tr("subtasks.deleteTitle") }
    public static var newSubtaskTitle: String { NexusL10n.tr("subtasks.new") }

    public static func progress(completed: Int, total: Int, locale: Locale = .autoupdatingCurrent) -> String {
        NexusL10n.format("subtasks.progress", locale: locale, completed, total)
    }

    public static func deleteWithDescendantsMessage(count: Int, locale: Locale = .autoupdatingCurrent) -> String {
        NexusL10n.format("subtasks.deleteDescendants", locale: locale, count)
    }

    public static func deleteWithPromotionMessage(count: Int, locale: Locale = .autoupdatingCurrent) -> String {
        NexusL10n.format("subtasks.deletePromote", locale: locale, count)
    }

    // Legacy format placeholders used by older call sites with String(format:).
    public static var deleteWithDescendantsMessageFormat: String { NexusL10n.tr("subtasks.deleteDescendants") }
    public static var deleteWithPromotionMessageFormat: String { NexusL10n.tr("subtasks.deletePromote") }
}
