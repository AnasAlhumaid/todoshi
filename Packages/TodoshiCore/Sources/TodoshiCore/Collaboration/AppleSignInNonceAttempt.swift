import Foundation

/// One Sign in with Apple attempt: generate raw nonce once, hash for Apple, pass raw to Firebase.
public struct AppleSignInNonceAttempt: Sendable, Equatable {
    public let rawNonce: String

    public init(rawNonce: String) {
        self.rawNonce = rawNonce
    }

    public static func make() -> AppleSignInNonceAttempt {
        AppleSignInNonceAttempt(rawNonce: AppleSignInNonce.randomNonce())
    }

    /// Value for `ASAuthorizationAppleIDRequest.nonce`.
    public var hashedNonceForApple: String {
        AppleSignInNonce.sha256(rawNonce)
    }

    /// Value for Firebase `OAuthProvider.appleCredential(..., rawNonce:)`.
    public var rawNonceForFirebase: String {
        rawNonce
    }
}

public enum AppleIdentityTokenPolicy: Sendable {
    /// Decodes Apple's identity-token Data into a UTF-8 string without logging contents.
    public static func utf8String(from data: Data?) -> String? {
        guard let data else { return nil }
        guard let string = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
