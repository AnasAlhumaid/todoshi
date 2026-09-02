import Foundation

/// Small in-memory/UserDefaults-backed recent search list logic.
public enum RecentSearchesStore: Sendable {
    public static let storageKey = "nexus.search.recentTerms"
    public static let maxTerms = 5

    public static func normalizeTerm(_ raw: String) -> String? {
        let term = SearchText.normalizeQuery(raw)
        return term.isEmpty ? nil : term
    }

    /// Inserts `raw` at front, case-insensitive dedupe, capped at `maxTerms`.
    public static func recording(_ raw: String, into existing: [String]) -> [String] {
        guard let term = normalizeTerm(raw) else { return existing }
        var next = existing.filter {
            $0.compare(term, options: SearchText.compareOptions) != .orderedSame
        }
        next.insert(term, at: 0)
        if next.count > maxTerms {
            next = Array(next.prefix(maxTerms))
        }
        return next
    }

    public static func deleting(_ raw: String, from existing: [String]) -> [String] {
        guard let term = normalizeTerm(raw) else { return existing }
        return existing.filter {
            $0.compare(term, options: SearchText.compareOptions) != .orderedSame
        }
    }

    public static func clearing() -> [String] {
        []
    }

    public static func load(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: storageKey) ?? []
    }

    public static func save(_ terms: [String], to defaults: UserDefaults = .standard) {
        defaults.set(terms, forKey: storageKey)
    }
}

public enum SearchPreferences: Sendable {
    public static let includeArchivedKey = "nexus.search.includeArchived"
}
