import Foundation

/// Pure validation and uniqueness for global label names.
public enum LabelValidation: Sendable {
    public static let maxNameLength = 30

    public enum Issue: Equatable, Sendable {
        case emptyName
        case tooLong
        case duplicateName
        case invalidColor
    }

    /// Trims edges and collapses internal whitespace; does not lower-case.
    public static func normalizeDisplayName(_ raw: String) -> String {
        SearchText.normalizeQuery(raw)
    }

    public static func compareKey(_ name: String, locale: Locale = .current) -> String {
        let display = normalizeDisplayName(name)
        return display.folding(options: SearchText.compareOptions, locale: locale)
    }

    public static func namesConflict(
        _ lhs: String,
        _ rhs: String,
        locale: Locale = .current
    ) -> Bool {
        compareKey(lhs, locale: locale) == compareKey(rhs, locale: locale)
            && !compareKey(lhs, locale: locale).isEmpty
    }

    public static func issue(
        name: String,
        colorHex: String,
        existingNames: [String],
        excludingLabelID: UUID? = nil,
        existingLabels: [(id: UUID, name: String)] = [],
        locale: Locale = .current
    ) -> Issue? {
        let cleaned = normalizeDisplayName(name)
        if cleaned.isEmpty { return .emptyName }
        if cleaned.count > maxNameLength { return .tooLong }

        let colorUpper = colorHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let validColor = LabelColorCatalog.swatches.contains { $0.hex.uppercased() == colorUpper }
        if !validColor { return .invalidColor }

        let key = compareKey(cleaned, locale: locale)
        if !existingLabels.isEmpty {
            for entry in existingLabels {
                if let excludingLabelID, entry.id == excludingLabelID { continue }
                if compareKey(entry.name, locale: locale) == key {
                    return .duplicateName
                }
            }
        } else {
            for other in existingNames {
                if namesConflict(cleaned, other, locale: locale) {
                    return .duplicateName
                }
            }
        }
        return nil
    }

    public static func message(for issue: Issue) -> String {
        switch issue {
        case .emptyName:
            return LabelStrings.nameRequired
        case .tooLong:
            return LabelStrings.nameTooLong
        case .duplicateName:
            return LabelStrings.duplicateName
        case .invalidColor:
            return LabelStrings.invalidColor
        }
    }
}
