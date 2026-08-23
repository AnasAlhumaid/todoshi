import Foundation

public struct TaskStatusShortcut: Equatable, Sendable {
    public let target: TaskStatus
    public let localizationKey: String

    public init(target: TaskStatus, localizationKey: String) {
        self.target = target
        self.localizationKey = localizationKey
    }

    public func label(locale: Locale = .autoupdatingCurrent) -> String {
        NexusL10n.tr(localizationKey, locale: locale)
    }
}

/// Common one-step status transitions for contextual shortcuts.
public enum TaskStatusShortcuts: Sendable {
    public static func primary(from status: TaskStatus) -> TaskStatusShortcut? {
        switch status {
        case .backlog:
            return TaskStatusShortcut(target: .todo, localizationKey: "task.statusShortcut.moveToReady")
        case .todo:
            return TaskStatusShortcut(target: .inProgress, localizationKey: "task.statusShortcut.startWork")
        case .inProgress:
            return TaskStatusShortcut(target: .review, localizationKey: "task.statusShortcut.sendForReview")
        case .review:
            return TaskStatusShortcut(target: .done, localizationKey: "task.statusShortcut.complete")
        case .done:
            return TaskStatusShortcut(target: .todo, localizationKey: "task.statusShortcut.reopen")
        }
    }
}
