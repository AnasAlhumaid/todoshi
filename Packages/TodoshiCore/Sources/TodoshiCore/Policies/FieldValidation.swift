import Foundation

/// Shared string validation for form saves.
public enum FieldValidation: Sendable {
    public static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns a non-empty trimmed name, or `nil` if empty after trim.
    public static func requiredName(_ value: String) -> String? {
        let trimmed = trimmed(value)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func isValidRequiredName(_ value: String) -> Bool {
        requiredName(value) != nil
    }
}
