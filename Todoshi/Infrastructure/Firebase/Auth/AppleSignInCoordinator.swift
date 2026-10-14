import AuthenticationServices
import Foundation
import TodoshiCore
import UIKit

struct AppleSignInCredentialPayload: Sendable {
    let identityToken: String
    let rawNonce: String
    /// Captured for future token revocation / account deletion only — not used for Firebase sign-in.
    let authorizationCode: String?
    let fullName: PersonNameComponents?
    let email: String?
}

/// Owns Apple ID authorization for Sign in with Apple.
/// Strongly retains ASAuthorizationController + delegate until completion.
@MainActor
final class AppleSignInCoordinator: NSObject {
    private var currentAttempt: AppleSignInNonceAttempt?
    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var activeController: ASAuthorizationController?
    private var presentationAnchorWindow: UIWindow?

    /// Configures an existing request (e.g. SwiftUI `SignInWithAppleButton` request builder).
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        let attempt = AppleSignInNonceAttempt.make()
        currentAttempt = attempt
        request.requestedScopes = [.fullName, .email]
        request.nonce = attempt.hashedNonceForApple
    }

    /// Programmatic Apple authorization for Sign in with Apple.
    /// Creates `ASAuthorizationController` and calls `performRequests()`.
    func signIn() async throws -> AppleSignInCredentialPayload {
        let authorization = try await performAuthorizationRequests()
        return try payload(from: authorization)
    }

    func payload(from authorization: ASAuthorization) throws -> AppleSignInCredentialPayload {
        guard let attempt = currentAttempt else {
            throw CollaborationError.appleCredentialUnavailable
        }
        defer { currentAttempt = nil }

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw CollaborationError.appleCredentialUnavailable
        }
        guard let identityToken = AppleIdentityTokenPolicy.utf8String(from: credential.identityToken) else {
            throw CollaborationError.missingIdentityToken
        }

        let authorizationCode = credential.authorizationCode.flatMap {
            String(data: $0, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let normalizedCode = authorizationCode.flatMap { $0.isEmpty ? nil : $0 }

        return AppleSignInCredentialPayload(
            identityToken: identityToken,
            rawNonce: attempt.rawNonceForFirebase,
            authorizationCode: normalizedCode,
            fullName: credential.fullName,
            email: credential.email
        )
    }

    func mapError(_ error: Error) -> CollaborationError {
        if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
            return .signInCancelled
        }
        return .appleCredentialUnavailable
    }

    // MARK: - ASAuthorizationController

    private func performAuthorizationRequests() async throws -> ASAuthorization {
        if continuation != nil {
            throw CollaborationError.appleCredentialUnavailable
        }

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        configure(request)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        activeController = controller
        controller.delegate = self
        controller.presentationContextProvider = self

        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion][Apple] ASAuthorizationController created")
        #endif

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            #if DEBUG
            TodoshiDiagnostics.note("[AccountDeletion][Apple] performRequests CALLED")
            #endif
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<ASAuthorization, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        activeController = nil
        presentationAnchorWindow = nil
        switch result {
        case .success(let authorization):
            continuation.resume(returning: authorization)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion][Apple] authorization SUCCESS")
        #endif
        finish(.success(authorization))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        #if DEBUG
        TodoshiDiagnostics.note(
            "[AccountDeletion][Apple] authorization FAILURE \(String(describing: mapError(error)))"
        )
        #endif
        finish(.failure(mapError(error)))
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let window = presentationAnchorWindow {
            return window
        }
        if let window = PresentingViewControllerResolver.resolve()?.viewController.view.window {
            presentationAnchorWindow = window
            return window
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        if let window = active?.windows.first(where: \.isKeyWindow) ?? active?.windows.first {
            presentationAnchorWindow = window
            return window
        }
        // Last resort — should not happen on a normal device foreground.
        let fallback = UIWindow(frame: UIScreen.main.bounds)
        presentationAnchorWindow = fallback
        return fallback
    }
}
