import Foundation

/// Pure validation for checklist item titles.
public enum ChecklistValidation: Sendable {
    public static let maxTitleLength = 120

    public enum Issue: Equatable, Sendable {
        case emptyTitle
        case tooLong
    }

    /// Trims edges and collapses internal whitespace; preserves user casing.
    public static func normalizeTitle(_ raw: String) -> String {
        SearchText.normalizeQuery(raw)
    }

    public static func issue(title: String) -> Issue? {
        let cleaned = normalizeTitle(title)
        if cleaned.isEmpty { return .emptyTitle }
        if cleaned.count > maxTitleLength { return .tooLong }
        return nil
    }

    public static func message(for issue: Issue) -> String {
        switch issue {
        case .emptyTitle:
            return ChecklistStrings.invalidItem
        case .tooLong:
            return ChecklistStrings.titleTooLong
        }
    }
}

public enum ChecklistStrings: Sendable {
    public static var checklist: String { TodoshiL10n.tr("checklist.title") }
    public static var addItem: String { TodoshiL10n.tr("checklist.addItem") }
    public static var editItem: String { TodoshiL10n.tr("checklist.editItem") }
    public static var deleteItem: String { TodoshiL10n.tr("checklist.deleteItem") }
    public static var markComplete: String { TodoshiL10n.tr("checklist.markComplete") }
    public static var markIncomplete: String { TodoshiL10n.tr("checklist.markIncomplete") }
    public static var completed: String { TodoshiL10n.tr("checklist.completed") }
    public static var itemsCompleted: String { TodoshiL10n.tr("checklist.itemsCompleted") }
    public static var noItems: String { TodoshiL10n.tr("checklist.noItems") }
    public static var invalidItem: String { TodoshiL10n.tr("checklist.invalidItem") }

    public static var titleTooLong: String {
        TodoshiL10n.format("checklist.titleTooLong", ChecklistValidation.maxTitleLength)
    }

    public static var progressFormat: String { TodoshiL10n.tr("checklist.progress") }

    public static func progress(completed: Int, total: Int, locale: Locale = AppLanguageStore.resolvedLocale) -> String {
        TodoshiL10n.format("checklist.progress", locale: locale, completed, total)
    }
}
