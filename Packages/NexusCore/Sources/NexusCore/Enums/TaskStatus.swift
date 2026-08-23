import Foundation

/// Kanban column for a root task.
public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case backlog
    case todo
    case inProgress
    case review
    case done

    public var displayName: String {
        displayName(locale: .autoupdatingCurrent)
    }

    public func displayName(locale: Locale) -> String {
        switch self {
        case .backlog: return NexusL10n.tr("status.backlog", locale: locale)
        case .todo: return NexusL10n.tr("status.todo", locale: locale)
        case .inProgress: return NexusL10n.tr("status.inProgress", locale: locale)
        case .review: return NexusL10n.tr("status.review", locale: locale)
        case .done: return NexusL10n.tr("status.done", locale: locale)
        }
    }
}
