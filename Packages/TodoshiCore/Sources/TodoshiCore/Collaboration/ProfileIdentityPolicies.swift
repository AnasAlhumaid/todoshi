import Foundation

public enum ProfileDisplayNameValidation: Sendable {
    public static let maximumLength = 60

    public enum Issue: Error, Sendable, Equatable {
        case empty
        case tooLong
    }

    /// Trims whitespace and validates a collaboration display name.
    public static func validated(_ raw: String) -> Result<String, Issue> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard trimmed.count <= maximumLength else { return .failure(.tooLong) }
        return .success(trimmed)
    }
}

/// Suppresses duplicate display of email when it is also used as the visible name.
public enum ProfileIdentityPresentation: Sendable {
    public struct Lines: Sendable, Equatable {
        public let primary: String
        public let secondary: String?

        public init(primary: String, secondary: String? = nil) {
            self.primary = primary
            self.secondary = secondary
        }
    }

    public static func lines(
        displayName: String?,
        email: String?,
        fallback: String
    ) -> Lines {
        let name = normalized(displayName)
        let mail = normalized(email)

        if let name {
            if let mail, !equalsIgnoringCase(name, mail) {
                return Lines(primary: name, secondary: mail)
            }
            return Lines(primary: name, secondary: nil)
        }
        // Email is an account field — never substitute it as the collaboration display name.
        if let mail {
            return Lines(primary: fallback, secondary: mail)
        }
        return Lines(primary: fallback, secondary: nil)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func equalsIgnoringCase(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

public enum ProfileAvatarInitialsPolicy: Sendable {
    /// Up to two initials from a display name; empty when no usable name.
    /// Latin initials are compacted (`AH`); non-Latin pairs are space-separated (`أ ح`).
    public static func initials(from displayName: String?) -> String {
        guard let displayName else { return "" }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let parts = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        if parts.count >= 2,
           let first = significantInitial(from: parts[0]),
           let second = significantInitial(from: parts[1]) {
            let left = String(first)
            let right = String(second)
            if first.isASCII && second.isASCII {
                return (left + right).uppercased()
            }
            return "\(left) \(right)"
        }
        if let only = parts.first.flatMap({ significantInitial(from: $0) }) {
            let value = String(only)
            return only.isASCII ? value.uppercased() : value
        }
        return ""
    }

    /// Whether the UI should show the system person icon instead of initials.
    public static func shouldShowPersonIcon(for displayName: String?) -> Bool {
        initials(from: displayName).isEmpty
    }

    /// Skips a leading Arabic definite article (`ال`) so "الحميد" yields "ح".
    private static func significantInitial(from word: String) -> Character? {
        var candidate = word
        if candidate.hasPrefix("ال"), candidate.count > 2 {
            candidate = String(candidate.dropFirst(2))
        }
        return candidate.first
    }
}

/// Stable Storage path helpers retained for a future Firebase Storage phase.
/// Current MVP does not upload or persist avatars.
public enum ProfileAvatarPathPolicy: Sendable {
    public static let fileName = "avatar.jpg"

    public static func path(forUserID uid: String) -> String? {
        let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.contains("/") else { return nil }
        return "profile-images/\(trimmed)/\(fileName)"
    }

    public static func isValid(_ path: String, forUserID uid: String) -> Bool {
        path == Self.path(forUserID: uid)
    }

    public static func userID(from path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 3,
              parts[0] == "profile-images",
              parts[2] == fileName,
              !parts[1].isEmpty else {
            return nil
        }
        return parts[1]
    }
}
