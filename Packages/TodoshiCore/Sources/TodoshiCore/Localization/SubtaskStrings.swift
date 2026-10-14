import Foundation

public enum SubtaskStrings: Sendable {
    public static var subtasks: String { TodoshiL10n.tr("subtasks.title") }
    public static var subtask: String { TodoshiL10n.tr("subtasks.subtask") }
    public static var addSubtask: String { TodoshiL10n.tr("subtasks.add") }
    public static var subtaskOf: String { TodoshiL10n.tr("subtasks.of") }
    public static var promoteToRoot: String { TodoshiL10n.tr("subtasks.promote") }
    public static var deleteParent: String { TodoshiL10n.tr("subtasks.deleteParent") }
    public static var deleteAllSubtasks: String { TodoshiL10n.tr("subtasks.deleteAll") }
    public static var promoteSubtasks: String { TodoshiL10n.tr("subtasks.promoteAll") }
    public static var completedSubtasks: String { TodoshiL10n.tr("subtasks.completed") }
    public static var noSubtasks: String { TodoshiL10n.tr("subtasks.none") }
    public static var cannotAddNested: String { TodoshiL10n.tr("subtasks.cannotNested") }
    public static var parentTask: String { TodoshiL10n.tr("subtasks.parent") }
    public static var invalidParent: String { TodoshiL10n.tr("subtasks.invalidParent") }
    public static var sameProjectRequired: String { TodoshiL10n.tr("subtasks.sameProject") }
    public static var progressFormat: String { TodoshiL10n.tr("subtasks.progress") }
    public static var promoteConfirmTitle: String { TodoshiL10n.tr("subtasks.promoteTitle") }
    public static var promoteConfirmMessage: String { TodoshiL10n.tr("subtasks.promoteMessage") }
    public static var deleteTaskTitle: String { TodoshiL10n.tr("subtasks.deleteTitle") }
    public static var newSubtaskTitle: String { TodoshiL10n.tr("subtasks.new") }

    public static func progress(completed: Int, total: Int, locale: Locale = .autoupdatingCurrent) -> String {
        TodoshiL10n.format("subtasks.progress", locale: locale, completed, total)
    }

    public static func deleteWithDescendantsMessage(count: Int, locale: Locale = .autoupdatingCurrent) -> String {
        TodoshiL10n.format("subtasks.deleteDescendants", locale: locale, count)
    }

    public static func deleteWithPromotionMessage(count: Int, locale: Locale = .autoupdatingCurrent) -> String {
        TodoshiL10n.format("subtasks.deletePromote", locale: locale, count)
    }

    // Legacy format placeholders used by older call sites with String(format:).
    public static var deleteWithDescendantsMessageFormat: String { TodoshiL10n.tr("subtasks.deleteDescendants") }
    public static var deleteWithPromotionMessageFormat: String { TodoshiL10n.tr("subtasks.deletePromote") }
}
