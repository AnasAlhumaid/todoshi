import Foundation

/// Public identity document at `publicIdentities/{uid}` — no email or display name.
public struct TodoshiPublicIdentity: Sendable, Equatable {
    public let userID: String
    public let todoshiId: String
    public let createdAt: Date?

    public init(userID: String, todoshiId: String, createdAt: Date? = nil) {
        self.userID = userID
        self.todoshiId = todoshiId
        self.createdAt = createdAt
    }
}
