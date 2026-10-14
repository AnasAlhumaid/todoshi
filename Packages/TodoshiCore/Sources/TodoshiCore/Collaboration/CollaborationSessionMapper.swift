import Foundation

public enum CollaborationSessionMapper: Sendable {
    public struct UserInput: Sendable, Equatable {
        public let id: String
        public let displayName: String?
        public let email: String?

        public init(id: String, displayName: String? = nil, email: String? = nil) {
            self.id = id
            self.displayName = displayName
            self.email = email
        }
    }

    public static func session(from user: UserInput) -> CollaborationSession? {
        guard FirebaseIdentifierPolicy.isValidFirebaseUserID(user.id) else { return nil }
        return CollaborationSession(
            user: CollaborationUser(
                id: user.id,
                displayName: user.displayName,
                email: user.email
            )
        )
    }
}
