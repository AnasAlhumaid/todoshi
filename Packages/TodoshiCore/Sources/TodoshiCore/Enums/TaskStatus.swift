import Foundation

/// Kanban column for a root task.
public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case backlog
    case todo
    case inProgress
    case review
    case done

    public var displayName: String {
        displayName(locale: AppLanguageStore.resolvedLocale)
    }

    public func displayName(locale: Locale) -> String {
        switch self {
        case .backlog: return TodoshiL10n.tr("status.backlog", locale: locale)
        case .todo: return TodoshiL10n.tr("status.todo", locale: locale)
        case .inProgress: return TodoshiL10n.tr("status.inProgress", locale: locale)
        case .review: return TodoshiL10n.tr("status.review", locale: locale)
        case .done: return TodoshiL10n.tr("status.done", locale: locale)
        }
    }
}
