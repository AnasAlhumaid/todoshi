import Foundation

public struct CollaborationUser: Sendable, Equatable {
    public let id: String
    public let displayName: String?
    public let email: String?

    public init(id: String, displayName: String? = nil, email: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.email = email
    }
}

public struct CollaborationSession: Sendable, Equatable {
    public let user: CollaborationUser

    public init(user: CollaborationUser) {
        self.user = user
    }
}
