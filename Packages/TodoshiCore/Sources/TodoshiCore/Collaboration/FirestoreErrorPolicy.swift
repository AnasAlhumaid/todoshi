import Foundation

public enum FirestoreErrorPolicy: Sendable {
    public static let errorDomain = "FIRFirestoreErrorDomain"

    /// Common `Firestore.FirestoreErrorCode` numeric values.
    public static let notFoundCode = 5
    public static let permissionDeniedCode = 7
    public static let failedPreconditionCode = 9
    public static let unavailableCode = 14

    public enum Classification: String, Sendable, Equatable {
        case permissionDenied
        case unavailable
        case notFound
        case failedPrecondition
        case other
    }

    public struct DebugInfo: Sendable, Equatable {
        public let domain: String
        public let code: Int
        public let classification: Classification

        public init(domain: String, code: Int, classification: Classification) {
            self.domain = domain
            self.code = code
            self.classification = classification
        }
    }

    public static func debugInfo(for error: Error) -> DebugInfo {
        let nsError = error as NSError
        return DebugInfo(
            domain: nsError.domain,
            code: nsError.code,
            classification: classify(error)
        )
    }

    public static func classify(_ error: Error) -> Classification {
        let nsError = error as NSError
        guard nsError.domain == errorDomain else { return .other }
        switch nsError.code {
        case permissionDeniedCode:
            return .permissionDenied
        case unavailableCode:
            return .unavailable
        case notFoundCode:
            return .notFound
        case failedPreconditionCode:
            return .failedPrecondition
        default:
            return .other
        }
    }
}

/// Builds a Firestore-safe profile merge payload without writing nil optional values.
public enum FirestoreUserProfilePayloadPolicy: Sendable {
    public struct Payload: Sendable, Equatable {
        public let displayName: String?
        public let email: String?
        public let includeCreatedAt: Bool

        public init(
            displayName: String?,
            email: String?,
            includeCreatedAt: Bool
        ) {
            self.displayName = displayName
            self.email = email
            self.includeCreatedAt = includeCreatedAt
        }

        public var fieldKeys: Set<String> {
            var keys: Set<String> = ["updatedAt"]
            if includeCreatedAt { keys.insert("createdAt") }
            if displayName != nil { keys.insert("displayName") }
            if email != nil { keys.insert("email") }
            return keys
        }
    }

    public static func payload(
        existing: FirebaseUserProfileFields?,
        incoming: FirebaseUserProfileFields,
        documentExists: Bool
    ) -> Payload {
        let merged = FirebaseUserProfileMergePolicy.merged(existing: existing, incoming: incoming)
        return Payload(
            displayName: merged.displayName,
            email: merged.email,
            includeCreatedAt: !documentExists
        )
    }
}
