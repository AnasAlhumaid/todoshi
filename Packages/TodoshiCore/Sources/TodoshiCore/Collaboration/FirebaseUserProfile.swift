import Foundation

public struct FirebaseUserProfileDTO: Codable, Sendable, Equatable {
    public let displayName: String?
    public let email: String?
    public let avatarPath: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        displayName: String?,
        email: String?,
        avatarPath: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.displayName = displayName
        self.email = email
        self.avatarPath = avatarPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct FirebaseUserProfileFields: Sendable, Equatable {
    public var displayName: String?
    public var email: String?
    public var avatarPath: String?
    public var todoshiId: String?

    public init(
        displayName: String? = nil,
        email: String? = nil,
        avatarPath: String? = nil,
        todoshiId: String? = nil
    ) {
        self.displayName = displayName
        self.email = email
        self.avatarPath = avatarPath
        self.todoshiId = todoshiId
    }
}

public enum FirebaseUserProfileMergePolicy: Sendable {
    /// Preserves existing non-empty profile values when Apple/Firebase omit them on later sign-ins.
    public static func merged(
        existing: FirebaseUserProfileFields?,
        incoming: FirebaseUserProfileFields
    ) -> FirebaseUserProfileFields {
        FirebaseUserProfileFields(
            displayName: preferred(existing?.displayName, incoming.displayName),
            email: preferred(existing?.email, incoming.email),
            avatarPath: preferred(existing?.avatarPath, incoming.avatarPath),
            todoshiId: preferredTodoshiId(existing?.todoshiId, incoming.todoshiId)
        )
    }

    private static func preferred(_ existing: String?, _ incoming: String?) -> String? {
        let trimmedExisting = existing?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedExisting, !trimmedExisting.isEmpty { return trimmedExisting }
        let trimmedIncoming = incoming?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedIncoming, !trimmedIncoming.isEmpty { return trimmedIncoming }
        return nil
    }

    /// Todoshi ID is immutable once assigned; never replace with incoming profile sync values.
    private static func preferredTodoshiId(_ existing: String?, _ incoming: String?) -> String? {
        TodoshiIdentityProvisioningPolicy.normalized(existing)
            ?? TodoshiIdentityProvisioningPolicy.normalized(incoming)
    }
}

/// Collaboration identity loaded from `users/{uid}` for profile UI.
public struct CollaborationProfile: Sendable, Equatable {
    public let userID: String
    public var displayName: String?
    public var email: String?
    public var avatarPath: String?
    public var todoshiId: String?

    public init(
        userID: String,
        displayName: String? = nil,
        email: String? = nil,
        avatarPath: String? = nil,
        todoshiId: String? = nil
    ) {
        self.userID = userID
        self.displayName = displayName
        self.email = email
        self.avatarPath = avatarPath
        self.todoshiId = todoshiId
    }
}
