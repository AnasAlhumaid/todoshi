import Foundation

/// Pure text normalization for local search matching.
public enum SearchText: Sendable {
    public static let compareOptions: String.CompareOptions = [
        .caseInsensitive,
        .diacriticInsensitive,
        .widthInsensitive
    ]

    /// Trims edges and collapses internal whitespace runs to a single space.
    public static func normalizeQuery(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let parts = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    public static func isEmptyQuery(_ raw: String) -> Bool {
        normalizeQuery(raw).isEmpty
    }

    /// Returns whether `text` contains `query` using locale-aware, case/diacritic-insensitive matching.
    public static func matches(
        _ text: String,
        query: String,
        locale: Locale = .current
    ) -> Bool {
        let q = normalizeQuery(query)
        guard !q.isEmpty else { return false }
        return text.range(
            of: q,
            options: compareOptions,
            range: nil,
            locale: locale
        ) != nil
    }

    public static func isExactMatch(
        _ text: String,
        query: String,
        locale: Locale = .current
    ) -> Bool {
        let q = normalizeQuery(query)
        guard !q.isEmpty else { return false }
        return text.compare(q, options: compareOptions, range: nil, locale: locale) == .orderedSame
    }

    public static func isPrefixMatch(
        _ text: String,
        query: String,
        locale: Locale = .current
    ) -> Bool {
        let q = normalizeQuery(query)
        guard !q.isEmpty else { return false }
        return text.range(
            of: q,
            options: compareOptions.union(.anchored),
            range: nil,
            locale: locale
        ) != nil
    }
}
