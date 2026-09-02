import Foundation

#if DEBUG
/// Debug-only localization completeness audit (not shown in Release UI).
public enum LocalizationAudit {
    /// High-traffic keys that must resolve in English and Arabic without echoing the key.
    public static let criticalKeys: [String] = [
        "tab.dashboard", "tab.projects", "tab.calendar", "tab.search", "tab.settings",
        "home.projectActions", "project.new", "project.archivedTitle",
        "status.backlog", "status.todo", "status.inProgress", "status.review", "status.done",
        "priority.none", "priority.low", "priority.medium", "priority.high", "priority.urgent",
        "widget.today", "widget.nothingToday", "widget.highPriority", "widget.noOpenTasks",
        "widget.previousProject", "widget.nextProject", "widget.fullEditor", "widget.chooseProject",
        "intent.addTask.title", "intent.taskAdded", "intent.unableAdd", "intent.taskTitle",
        "notification.dailySummary", "notification.enableTitle",
        "error.genericSave", "error.missingTask", "error.storeUnavailable",
        "checklist.progress", "recurrence.daily", "resource.code",
        "common.cancel", "common.save", "common.delete",
    ]

    public struct Finding: Sendable, Hashable {
        public let key: String
        public let localeID: String
        public let reason: String
    }

    /// Returns missing or unresolved keys for the locales `en` and `ar`.
    public static func audit(locales: [Locale] = [Locale(identifier: "en"), Locale(identifier: "ar")]) -> [Finding] {
        var findings: [Finding] = []
        for locale in locales {
            let id = locale.identifier
            for key in criticalKeys {
                let value = NexusL10n.tr(key, locale: locale)
                if value.isEmpty {
                    findings.append(Finding(key: key, localeID: id, reason: "empty"))
                } else if value == key {
                    findings.append(Finding(key: key, localeID: id, reason: "unresolved key echo"))
                }
            }
        }
        return findings
    }
}
#endif
