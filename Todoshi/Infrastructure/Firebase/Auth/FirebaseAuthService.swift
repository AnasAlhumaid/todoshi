import Foundation
import FirebaseAuth
import TodoshiCore

struct FirebaseAuthUserSnapshot: Sendable {
    let uid: String
    let displayName: String?
    let email: String?
}

@MainActor
final class FirebaseAuthService {
    static let shared = FirebaseAuthService()

    private init() {}

    var isConfigured: Bool {
        FirebaseBootstrap.isConfigured
    }

    func currentSession() -> CollaborationSession? {
        guard isConfigured, let user = Auth.auth().currentUser else { return nil }
        return mapSession(user: user)
    }

    func addStateListener(_ handler: @escaping @Sendable (CollaborationSession?) -> Void) -> AuthStateDidChangeListenerHandle? {
        guard isConfigured else {
            handler(nil)
            return nil
        }
        return Auth.auth().addStateDidChangeListener { _, user in
            let session = user.flatMap { Self.mapSession(user: $0) }
            handler(session)
        }
    }

    func removeStateListener(_ handle: AuthStateDidChangeListenerHandle?) {
        guard isConfigured, let handle else { return }
        Auth.auth().removeStateDidChangeListener(handle)
    }

    /// Signs in with Firebase using Apple's ID token + the same raw nonce used for the Apple request.
    /// `authorizationCode` is intentionally unused here (reserved for future token revocation).
    func signInWithApple(
        identityToken: String,
        rawNonce: String,
        fullName: PersonNameComponents?,
        email: String?
    ) async throws {
        guard isConfigured else { throw CollaborationError.notConfigured }

        let credential = OAuthProvider.appleCredential(
            withIDToken: identityToken,
            rawNonce: rawNonce,
            fullName: fullName
        )

        #if DEBUG
        logPreSignInDiagnostics(identityToken: identityToken)
        TodoshiDiagnostics.note("[Auth] Firebase credential exchange started")
        #endif

        do {
            let result = try await Auth.auth().signIn(with: credential)
            #if DEBUG
            TodoshiDiagnostics.note("[Auth] Firebase credential exchange succeeded")
            TodoshiDiagnostics.note("[Auth] Firebase user authenticated")
            #endif
            await applyFirstSignInProfileIfNeeded(
                user: result.user,
                fullName: fullName,
                email: email
            )
        } catch {
            #if DEBUG
            logFirebaseSignInFailure(error)
            if let mapped = FirebaseAuthErrorPolicy.collaborationError(for: error) {
                TodoshiDiagnostics.note("[Auth] user-facing mapping=\(String(describing: mapped))")
            }
            #endif
            if let mapped = FirebaseAuthErrorPolicy.collaborationError(for: error) {
                throw mapped
            }
            throw CollaborationError.signInFailed
        }
    }

    /// Signs in with Firebase using Google ID + access tokens from Google Sign-In.
    func signInWithGoogle(
        idToken: String,
        accessToken: String,
        displayName: String?,
        email: String?
    ) async throws {
        guard isConfigured else { throw CollaborationError.notConfigured }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: accessToken
        )

        #if DEBUG
        TodoshiDiagnostics.note("[Auth] Firebase Google credential exchange started")
        #endif

        do {
            let result = try await Auth.auth().signIn(with: credential)
            #if DEBUG
            TodoshiDiagnostics.note("[Auth] Firebase Google credential succeeded")
            TodoshiDiagnostics.note("[Auth] Firebase user authenticated")
            #endif
            await applyDisplayNameIfNeeded(user: result.user, displayName: displayName)
            _ = email
        } catch {
            #if DEBUG
            logFirebaseSignInFailure(error)
            if let mapped = FirebaseAuthErrorPolicy.collaborationError(for: error) {
                TodoshiDiagnostics.note("[Auth] user-facing mapping=\(String(describing: mapped))")
            }
            #endif
            if let mapped = FirebaseAuthErrorPolicy.collaborationError(for: error) {
                throw mapped
            }
            throw CollaborationError.googleSignInFailed
        }
    }

    func signOut() throws {
        guard isConfigured else { return }
        try Auth.auth().signOut()
    }

    /// Provider IDs attached to the current Firebase user (e.g. `apple.com`, `google.com`).
    func currentProviderIDs() -> [String] {
        guard isConfigured, let user = Auth.auth().currentUser else { return [] }
        return user.providerData.map(\.providerID)
    }

    func resolvedDeletionProvider() -> AccountDeletionAuthProvider {
        AccountDeletionPlanningPolicy.resolveAuthProvider(providerIDs: currentProviderIDs())
    }

    /// Deletes the Firebase Auth user. Must run AFTER Firestore cleanup.
    /// On `auth/requires-recent-login`, throws `.accountDeletionRequiresReauthentication`
    /// — callers must NOT launch provider reauthentication UI.
    func deleteCurrentUser() async throws {
        guard isConfigured else { throw CollaborationError.notConfigured }
        guard let user = Auth.auth().currentUser else {
            throw CollaborationError.notAuthenticated
        }
        do {
            try await user.delete()
        } catch {
            if let mapped = FirebaseAuthErrorPolicy.collaborationError(for: error) {
                throw mapped
            }
            throw CollaborationError.accountDeletionFailed
        }
    }

    /// Keeps Firebase Auth profile display name aligned with Firestore after an explicit profile edit.
    func updateDisplayName(uid: String, displayName: String) async {
        guard isConfigured,
              let user = Auth.auth().currentUser,
              user.uid == uid,
              let normalized = CollaborationDisplayNamePolicy.normalized(displayName)
        else { return }
        await applyDisplayNameIfNeeded(user: user, displayName: normalized, force: true)
    }

    #if DEBUG
    private func logPreSignInDiagnostics(identityToken: String) {
        let identity = AuthRuntimeIdentityAudit.report(bundleIdentifier: Bundle.main.bundleIdentifier)
        TodoshiDiagnostics.note("[Auth] runtime bundleIdentifier=\(identity.bundleIdentifier ?? "nil")")
        TodoshiDiagnostics.note("[Auth] bundleIdentifierMatchesExpected=\(identity.bundleIdentifierMatchesExpected)")

        let claims = AppleIdentityTokenDiagnostics.report(for: identityToken)
        TodoshiDiagnostics.note("[Auth] identityTokenPresent=\(claims.identityTokenPresent)")
        TodoshiDiagnostics.note("[Auth] issuerIsApple=\(claims.issuerIsApple)")
        TodoshiDiagnostics.note("[Auth] audienceMatchesExpected=\(claims.audienceMatchesExpected)")
        TodoshiDiagnostics.note("[Auth] nonceClaimPresent=\(claims.nonceClaimPresent)")
    }

    private func logFirebaseSignInFailure(_ error: Error) {
        let info = FirebaseAuthErrorPolicy.debugInfo(for: error)
        TodoshiDiagnostics.note("[Auth] Firebase sign-in failed")
        TodoshiDiagnostics.note("domain=\(info.domain)")
        TodoshiDiagnostics.note("code=\(info.code)")
        if let name = info.name {
            TodoshiDiagnostics.note("name=\(name)")
        }
        TodoshiDiagnostics.note("classification=\(info.classification.rawValue)")
        if info.classification == .missingOrInvalidNonce {
            TodoshiDiagnostics.note("[Auth] Apple/Firebase nonce verification failed")
        }
    }
    #endif

    private func applyFirstSignInProfileIfNeeded(
        user: User,
        fullName: PersonNameComponents?,
        email: String?
    ) async {
        let appleDisplayName = CollaborationDisplayNamePolicy.fromAppleFullName(fullName)
        await applyDisplayNameIfNeeded(user: user, displayName: appleDisplayName)
        _ = email
    }

    private func applyDisplayNameIfNeeded(
        user: User,
        displayName: String?,
        force: Bool = false
    ) async {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return }
        guard force || user.displayName?.isEmpty != false else { return }

        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = trimmed
        do {
            try await changeRequest.commitChanges()
        } catch {
            #if DEBUG
            let nsError = error as NSError
            TodoshiDiagnostics.note("[Auth] Firebase profile update skipped: \(nsError.domain)/\(nsError.code)")
            #endif
        }
    }

    private static func mapSession(user: User) -> CollaborationSession? {
        CollaborationSessionMapper.session(
            from: CollaborationSessionMapper.UserInput(
                id: user.uid,
                displayName: user.displayName,
                email: user.email
            )
        )
    }

    private func mapSession(user: User) -> CollaborationSession? {
        Self.mapSession(user: user)
    }
}
