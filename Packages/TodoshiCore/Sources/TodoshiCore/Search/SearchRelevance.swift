import Foundation

/// Higher scores rank first.
public enum SearchRelevance: Sendable {
    public static let exactName = 1_000
    public static let prefixName = 800
    public static let containsName = 600
    public static let projectNameMatch = 500
    public static let labelMatch = 400
    public static let descriptionMatch = 300
    public static let notesMatch = 200
    public static let otherField = 100

    public static func projectScore(
        name: String,
        description: String,
        query: String,
        locale: Locale = .current
    ) -> Int {
        let q = SearchText.normalizeQuery(query)
        guard !q.isEmpty else { return 0 }

        if SearchText.isExactMatch(name, query: q, locale: locale) {
            return exactName
        }
        if SearchText.isPrefixMatch(name, query: q, locale: locale) {
            return prefixName
        }
        if SearchText.matches(name, query: q, locale: locale) {
            return containsName
        }
        if SearchText.matches(description, query: q, locale: locale) {
            return descriptionMatch
        }
        return 0
    }

    public static func taskScore(
        title: String,
        projectName: String,
        description: String,
        notes: String,
        labelNames: [String],
        query: String,
        locale: Locale = .current
    ) -> Int {
        let q = SearchText.normalizeQuery(query)
        guard !q.isEmpty else { return 0 }

        if SearchText.isExactMatch(title, query: q, locale: locale) {
            return exactName
        }
        if SearchText.isPrefixMatch(title, query: q, locale: locale) {
            return prefixName
        }
        if SearchText.matches(title, query: q, locale: locale) {
            return containsName
        }
        if SearchText.matches(projectName, query: q, locale: locale) {
            return projectNameMatch
        }
        if labelNames.contains(where: { SearchText.matches($0, query: q, locale: locale) }) {
            return labelMatch
        }
        if SearchText.matches(description, query: q, locale: locale) {
            return descriptionMatch
        }
        if SearchText.matches(notes, query: q, locale: locale) {
            return notesMatch
        }
        return 0
    }
}
