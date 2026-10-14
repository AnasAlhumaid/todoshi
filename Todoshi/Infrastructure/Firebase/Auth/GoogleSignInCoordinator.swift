import Foundation
import FirebaseCore
import GoogleSignIn
import TodoshiCore
import UIKit

struct GoogleSignInCredentialPayload: Sendable {
    let idToken: String
    let accessToken: String
    let displayName: String?
    let email: String?
}

@MainActor
final class GoogleSignInCoordinator {
    /// Interactive Google Sign-In that always presents and returns a fresh credential.
    /// Never treats `GIDSignIn.sharedInstance.currentUser` as sufficient by itself.
    func signIn(presenting viewController: UIViewController? = nil) async throws -> GoogleSignInCredentialPayload {
        guard let clientID = FirebaseApp.app()?.options.clientID,
              !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CollaborationError.notConfigured
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let resolution = PresentingViewControllerResolver.resolve(base: viewController) else {
            throw CollaborationError.googlePresentationFailed
        }
        let presenter = resolution.viewController

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)

            guard let idToken = result.user.idToken?.tokenString,
                  !idToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw CollaborationError.missingIdentityToken
            }

            let accessToken = result.user.accessToken.tokenString
            guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CollaborationError.googleCredentialUnavailable
            }

            let profile = result.user.profile
            return GoogleSignInCredentialPayload(
                idToken: idToken,
                accessToken: accessToken,
                displayName: profile?.name,
                email: profile?.email
            )
        } catch let error as CollaborationError {
            throw error
        } catch {
            throw GoogleSignInErrorPolicy.collaborationError(for: error)
        }
    }

    /// Clears Google Sign-In presentation/session state. Does not revoke Google account access.
    func clearLocalSession() {
        GIDSignIn.sharedInstance.signOut()
    }

    func handle(url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}
