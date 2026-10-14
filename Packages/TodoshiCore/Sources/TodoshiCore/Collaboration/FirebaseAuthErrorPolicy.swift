import Foundation

public enum FirebaseAuthErrorPolicy: Sendable {
    public static let errorDomain = "FIRAuthErrorDomain"
    public static let errorNameKey = "FIRAuthErrorNameKey"

    /// `AuthErrorCode.requiresRecentLogin`
    public static let requiresRecentLoginCode = 17014
    /// `AuthErrorCode.missingOrInvalidNonce`
    public static let missingOrInvalidNonceCode = 17094
    /// `AuthErrorCode.invalidCredential`
    public static let invalidCredentialCode = 17004
    /// `AuthErrorCode.userDisabled`
    public static let userDisabledCode = 17005
    /// `AuthErrorCode.emailAlreadyInUse`
    public static let emailAlreadyInUseCode = 17007
    /// `AuthErrorCode.accountExistsWithDifferentCredential`
    public static let accountExistsWithDifferentCredentialCode = 17012
    /// `AuthErrorCode.credentialAlreadyInUse`
    public static let credentialAlreadyInUseCode = 17025
    /// `AuthErrorCode.operationNotAllowed`
    public static let operationNotAllowedCode = 17006
    /// `AuthErrorCode.networkError`
    public static let networkErrorCode = 17020
    /// `AuthErrorCode.internalError`
    public static let internalErrorCode = 17999

    public enum Classification: String, Sendable, Equatable {
        case missingOrInvalidNonce
        case invalidCredential
        case operationNotAllowed
        case networkError
        case userDisabled
        case accountExistsWithDifferentCredential
        case requiresRecentLogin
        case internalError
        case other
    }

    public struct DebugInfo: Sendable, Equatable {
        public let domain: String
        public let code: Int
        public let name: String?
        public let classification: Classification

        public init(domain: String, code: Int, name: String?, classification: Classification) {
            self.domain = domain
            self.code = code
            self.name = name
            self.classification = classification
        }
    }

    public static func debugInfo(for error: Error) -> DebugInfo {
        let nsError = error as NSError
        let name = nsError.userInfo[errorNameKey] as? String
        return DebugInfo(
            domain: nsError.domain,
            code: nsError.code,
            name: name,
            classification: classify(error)
        )
    }

    public static func classify(_ error: Error) -> Classification {
        let info = debugInfoCore(for: error)
        guard info.domain == errorDomain else { return .other }

        if isMissingOrInvalidNonce(error) { return .missingOrInvalidNonce }

        switch info.code {
        case requiresRecentLoginCode:
            return .requiresRecentLogin
        case invalidCredentialCode, 17008, 17011:
            return .invalidCredential
        case emailAlreadyInUseCode,
             accountExistsWithDifferentCredentialCode,
             credentialAlreadyInUseCode:
            return .accountExistsWithDifferentCredential
        case operationNotAllowedCode:
            return .operationNotAllowed
        case networkErrorCode:
            return .networkError
        case userDisabledCode:
            return .userDisabled
        case internalErrorCode:
            return .internalError
        default:
            if info.name == "ERROR_REQUIRES_RECENT_LOGIN" { return .requiresRecentLogin }
            if info.name == "ERROR_INVALID_CREDENTIAL" { return .invalidCredential }
            if info.name == "ERROR_EMAIL_ALREADY_IN_USE"
                || info.name == "ERROR_ACCOUNT_EXISTS_WITH_DIFFERENT_CREDENTIAL"
                || info.name == "ERROR_CREDENTIAL_ALREADY_IN_USE" {
                return .accountExistsWithDifferentCredential
            }
            if info.name == "ERROR_OPERATION_NOT_ALLOWED" { return .operationNotAllowed }
            if info.name == "ERROR_NETWORK_REQUEST_FAILED" { return .networkError }
            if info.name == "ERROR_USER_DISABLED" { return .userDisabled }
            if info.name == "ERROR_INTERNAL_ERROR" { return .internalError }
            return .other
        }
    }

    public static func isRequiresRecentLogin(_ error: Error) -> Bool {
        let info = debugInfoCore(for: error)
        guard info.domain == errorDomain else { return false }
        if info.code == requiresRecentLoginCode { return true }
        return info.name == "ERROR_REQUIRES_RECENT_LOGIN"
    }

    public static func isMissingOrInvalidNonce(_ error: Error) -> Bool {
        let info = debugInfoCore(for: error)
        guard info.domain == errorDomain else { return false }
        if info.code == missingOrInvalidNonceCode { return true }
        return info.name == "ERROR_MISSING_OR_INVALID_NONCE"
    }

    /// Maps Firebase Auth `NSError` values to collaboration auth errors without importing Firebase SDK.
    public static func collaborationError(for error: Error) -> CollaborationError? {
        let nsError = error as NSError
        guard nsError.domain == errorDomain else { return nil }

        if isMissingOrInvalidNonce(error) {
            return .signInFailed
        }
        if isRequiresRecentLogin(error) {
            return .accountDeletionRequiresReauthentication
        }

        switch classify(error) {
        case .requiresRecentLogin:
            return .accountDeletionRequiresReauthentication
        case .accountExistsWithDifferentCredential:
            return .accountExistsWithDifferentCredential
        case .invalidCredential:
            return .invalidCredential
        case .operationNotAllowed, .networkError, .userDisabled, .internalError, .other, .missingOrInvalidNonce:
            return .signInFailed
        }
    }

    private static func debugInfoCore(for error: Error) -> (domain: String, code: Int, name: String?) {
        let nsError = error as NSError
        let name = nsError.userInfo[errorNameKey] as? String
        return (nsError.domain, nsError.code, name)
    }
}
