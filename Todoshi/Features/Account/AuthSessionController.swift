import AuthenticationServices
import FirebaseAuth
import Foundation
import Observation
import TodoshiCore

@Observable
@MainActor
final class AuthSessionController {
    private(set) var state: AuthenticationState = .loading
    var isSigningIn = false
    var statusMessage: String?
    var profileSyncWarning: String?
    var identityProvisioningWarning: String?
    private(set) var cachedTodoshiID: String?
    private(set) var identityRevision = 0
    /// Bumped on sign-out / account deletion so Settings NavigationStack rebuilds at root.
    private(set) var sessionUIEpoch: UInt = 0
    var isPresentingAuthenticationSheet = false
    /// Project ID awaiting Share after Sign in with Apple completes.
    private(set) var pendingShareProjectID: UUID?
    /// Invite token awaiting acceptance after authentication completes.
    private(set) var pendingInviteToken: String?

    /// DEBUG-stable identity for proving a single live controller instance.
    var instanceID: ObjectIdentifier { ObjectIdentifier(self) }

    private let authService: FirebaseAuthService
    private let appleCoordinator: AppleSignInCoordinator
    private let googleCoordinator: GoogleSignInCoordinator
    private let profileService: FirestoreUserProfileService
    @ObservationIgnored private var authListenerHandle: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var identityProvisionTask: Task<Void, Never>?
    @ObservationIgnored private var postAuthPipelineTask: Task<Void, Never>?
    /// While account deletion owns Auth.delete() → local wipe, defer signed-out UI.
    @ObservationIgnored private var accountDeletionInProgress = false
    @ObservationIgnored private var deferredSignedOutFromListener = false
    /// After successful account deletion, ignore stale signed-in listener events until next explicit sign-in.
    @ObservationIgnored private var accountDeletionFinalized = false

    var configurationStatus: CollaborationConfigurationStatus {
        CollaborationConfigurationPolicy.status(isFirebaseConfigured: authService.isConfigured)
    }

    var currentSession: CollaborationSession? {
        if case .signedIn(let session) = state {
            return session
        }
        return nil
    }

    var authRequirement: CollaborationAuthRequirement {
        CollaborationAuthGate.requirement(for: currentSession)
    }

    init(
        authService: FirebaseAuthService = .shared,
        appleCoordinator: AppleSignInCoordinator = AppleSignInCoordinator(),
        googleCoordinator: GoogleSignInCoordinator = GoogleSignInCoordinator(),
        profileService: FirestoreUserProfileService = .shared
    ) {
        self.authService = authService
        self.appleCoordinator = appleCoordinator
        self.googleCoordinator = googleCoordinator
        self.profileService = profileService
        #if DEBUG
        TodoshiDiagnostics.note("[AuthSession] INIT instance=\(ObjectIdentifier(self))")
        #endif
    }

    func startListening() {
        guard authListenerHandle == nil else { return }

        guard authService.isConfigured else {
            state = .signedOut
            return
        }

        authListenerHandle = authService.addStateListener { [weak self] session in
            Task { @MainActor in
                self?.applyAuthSessionFromListener(session)
            }
        }
    }

    func stopListening() {
        authService.removeStateListener(authListenerHandle)
        authListenerHandle = nil
    }

    func configureAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        appleCoordinator.configure(request)
    }

    func handleAppleAuthorization(_ authorization: ASAuthorization) async {
        await completeAppleSignIn {
            try appleCoordinator.payload(from: authorization)
        }
    }

    func handleAppleAuthorizationFailure(_ error: Error) async {
        let mapped = appleCoordinator.mapError(error)
        if mapped == .signInCancelled {
            statusMessage = nil
        } else {
            statusMessage = UserFacingError.message(for: mapped)
        }
    }

    func signInWithGoogle() async {
        guard !isSigningIn else { return }
        guard authService.isConfigured else {
            statusMessage = UserFacingError.message(for: CollaborationError.notConfigured)
            return
        }

        isSigningIn = true
        statusMessage = nil
        profileSyncWarning = nil
        defer { isSigningIn = false }

        do {
            let payload = try await googleCoordinator.signIn()
            #if DEBUG
            TodoshiDiagnostics.note("[Auth] Google authorization succeeded")
            #endif

            try await authService.signInWithGoogle(
                idToken: payload.idToken,
                accessToken: payload.accessToken,
                displayName: payload.displayName,
                email: payload.email
            )

            try await finalizeAuthenticatedSession(preferredEmail: payload.email)
        } catch let error as CollaborationError where error == .signInCancelled {
            statusMessage = nil
        } catch {
            await recoverAuthenticatedSessionAfterFailure(fallbackError: error)
        }
    }

    private func completeAppleSignIn(
        payloadProvider: () throws -> AppleSignInCredentialPayload
    ) async {
        guard !isSigningIn else { return }
        guard authService.isConfigured else {
            statusMessage = UserFacingError.message(for: CollaborationError.notConfigured)
            return
        }

        isSigningIn = true
        statusMessage = nil
        profileSyncWarning = nil
        defer { isSigningIn = false }

        do {
            let payload = try payloadProvider()
            #if DEBUG
            TodoshiDiagnostics.note("[Auth] Apple authorization succeeded")
            #endif

            try await authService.signInWithApple(
                identityToken: payload.identityToken,
                rawNonce: payload.rawNonce,
                fullName: payload.fullName,
                email: payload.email
            )

            let appleDisplayName = CollaborationDisplayNamePolicy.fromAppleFullName(payload.fullName)
            try await finalizeAuthenticatedSession(
                preferredEmail: payload.email,
                preferredDisplayName: appleDisplayName
            )
        } catch let error as CollaborationError where error == .signInCancelled {
            statusMessage = nil
        } catch {
            await recoverAuthenticatedSessionAfterFailure(fallbackError: error)
        }
    }

    func signOut() async {
        statusMessage = nil
        profileSyncWarning = nil
        identityProvisioningWarning = nil
        cachedTodoshiID = nil
        identityRevision = 0
        identityProvisionTask?.cancel()
        identityProvisionTask = nil
        postAuthPipelineTask?.cancel()
        postAuthPipelineTask = nil
        clearPendingShareProject()
        clearPendingInviteToken()
        accountDeletionFinalized = false
        do {
            try authService.signOut()
            googleCoordinator.clearLocalSession()
            applySignedOutLocally(presentAuthenticationUI: false)
        } catch {
            statusMessage = UserFacingError.message(for: error)
        }
    }

    /// Clears local session state after Firebase Auth user.delete() already succeeded.
    /// Idempotent — safe to call more than once. Does not perform cloud cleanup.
    func applyAccountDeletedLocally() {
        #if DEBUG
        TodoshiDiagnostics.note("[AuthSession] ACCOUNT DELETE FINALIZE instance=\(instanceID)")
        TodoshiDiagnostics.note(
            "[AccountDeletion] Firebase currentUser=\(Auth.auth().currentUser == nil ? "nil" : "non-nil") instance=\(instanceID)"
        )
        TodoshiDiagnostics.note("[AccountDeletion] Applying local account deletion")
        TodoshiDiagnostics.note("[AccountDeletion] Session state before=\(debugStateLabel(state))")
        #endif

        statusMessage = nil
        profileSyncWarning = nil
        identityProvisioningWarning = nil
        cachedTodoshiID = nil
        identityRevision = 0
        identityProvisionTask?.cancel()
        identityProvisionTask = nil
        postAuthPipelineTask?.cancel()
        postAuthPipelineTask = nil
        clearPendingShareProject()
        clearPendingInviteToken()
        // Synchronous Google SDK cleanup — do not await a callback.
        googleCoordinator.clearLocalSession()
        SharedProjectSyncService.shared.stop()

        deferredSignedOutFromListener = false
        accountDeletionInProgress = false
        accountDeletionFinalized = true

        // Local Firebase / Google session teardown after Auth.currentUser.delete() succeeded.
        do {
            try Auth.auth().signOut()
        } catch {
            #if DEBUG
            TodoshiDiagnostics.note("[AccountDeletion] Auth.signOut after Auth.delete (best-effort)")
            #endif
        }
        googleCoordinator.clearLocalSession()

        // Stay on Settings with inline Sign In — do NOT auto-present AuthenticationView.
        applySignedOutLocally(presentAuthenticationUI: false)
        isPresentingAuthenticationSheet = false

        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion] Releasing auth-state gate")
        TodoshiDiagnostics.note(
            "[AccountDeletion] Auth currentUser=\(Auth.auth().currentUser == nil ? "nil" : "non-nil") instance=\(instanceID)"
        )
        TodoshiDiagnostics.note("[AccountDeletion] Session state after=\(debugStateLabel(state))")
        TodoshiDiagnostics.note(
            "[AccountDeletion] authSheet=\(isPresentingAuthenticationSheet) (must stay false)"
        )
        TodoshiDiagnostics.note("[AccountDeletion] Terminal success")
        TodoshiDiagnostics.note("[AuthSession] state=\(debugStateLabel(state))")
        TodoshiDiagnostics.note(
            "[AccountDeletionUI] terminal presentation authSheet=false sessionUIEpoch=\(sessionUIEpoch)"
        )
        Task { @MainActor in
            TodoshiDiagnostics.note(
                "[RootAuthUI] authInstance=\(self.instanceID) state=\(self.debugStateLabel(self.state))"
            )
        }
        #endif
    }

    /// Account deletion coordinator sets this so Auth.delete() cannot tear down UI mid-flight.
    func setAccountDeletionInProgress(_ inProgress: Bool) {
        accountDeletionInProgress = inProgress
        if !inProgress {
            #if DEBUG
            TodoshiDiagnostics.note("[AccountDeletion] Releasing auth-state gate")
            #endif
            reconcileAuthStateAfterDeletionGateReleased()
        }
    }

    func handleIncomingURL(_ url: URL) -> Bool {
        googleCoordinator.handle(url: url)
    }

    func presentAuthenticationSheet() {
        isPresentingAuthenticationSheet = true
    }

    func dismissAuthenticationSheet() {
        isPresentingAuthenticationSheet = false
    }

    /// Reflects an edited display name in local session state without waiting for Auth listener.
    func applyDisplayNameUpdate(_ displayName: String) {
        guard case .signedIn(let session) = state else { return }
        let updated = CollaborationSession(
            user: CollaborationUser(
                id: session.user.id,
                displayName: displayName,
                email: session.user.email
            )
        )
        state = .signedIn(updated)
    }

    func requireAuthenticationForCollaboration() -> CollaborationAuthRequirement {
        let requirement = authRequirement
        if case .requiresAuthentication = requirement {
            isPresentingAuthenticationSheet = true
        }
        return requirement
    }

    /// Ensures the authenticated user has a provisioned Todoshi ID before collaboration.
    func ensureCollaborationIdentityReady() async -> Bool {
        guard let uid = currentSession?.user.id else { return false }
        await ensureTodoshiIdentityProvisioned(for: uid)
        return cachedTodoshiID != nil
    }

    func rememberPendingShareProject(id: UUID) {
        pendingShareProjectID = id
    }

    func consumePendingShareProjectID() -> UUID? {
        let id = pendingShareProjectID
        pendingShareProjectID = nil
        return id
    }

    func clearPendingShareProject() {
        pendingShareProjectID = nil
    }

    func rememberPendingInviteToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ProjectInviteTokenGenerator.isValidFormat(trimmed) else { return }
        pendingInviteToken = trimmed
    }

    func consumePendingInviteToken() -> String? {
        let token = pendingInviteToken
        pendingInviteToken = nil
        return token
    }

    func clearPendingInviteToken() {
        pendingInviteToken = nil
    }

    private func applyAuthSessionFromListener(_ session: CollaborationSession?) {
        let firebaseUserIsNil = Auth.auth().currentUser == nil

        if let session {
            if AccountDeletionAuthRacePolicy.shouldIgnoreSignedInListenerEvent(
                accountDeletionInProgress: accountDeletionInProgress,
                accountDeletionFinalized: accountDeletionFinalized,
                firebaseCurrentUserIsNil: firebaseUserIsNil
            ) {
                #if DEBUG
                TodoshiDiagnostics.note("[AccountDeletion] ignored stale signed-in listener event")
                #endif
                if firebaseUserIsNil {
                    deferredSignedOutFromListener = true
                }
                return
            }

            // A real post-deletion sign-in clears the finalization latch.
            if accountDeletionFinalized {
                accountDeletionFinalized = false
            }
            deferredSignedOutFromListener = false
            #if DEBUG
            TodoshiDiagnostics.note("[Auth] auth state listener received signed-in user")
            #endif
            setAuthState(session)
            // Do not start post-auth provisioning while account deletion is tearing down.
            if accountDeletionInProgress { return }
            schedulePostAuthenticationPipeline(
                for: session,
                preferredEmail: session.user.email
            )
        } else if !isSigningIn {
            SharedProjectSyncService.shared.stop()
            if AccountDeletionAuthRacePolicy.shouldDeferSignedOutUI(
                deletionInProgress: accountDeletionInProgress
            ) {
                deferredSignedOutFromListener = true
                #if DEBUG
                TodoshiDiagnostics.note("[AccountDeletion] deferred signed-out UI during deletion")
                #endif
                return
            }
            if accountDeletionFinalized {
                // Keep authoritative signed-out presentation without opening auth sheet.
                if case .signedOut = state {
                    isPresentingAuthenticationSheet = false
                    return
                }
                applySignedOutLocally(presentAuthenticationUI: false)
                return
            }
            setAuthState(nil)
        }
    }

    /// Gate release / terminal finalization: Firebase currentUser is final authority.
    private func reconcileAuthStateAfterDeletionGateReleased() {
        let firebaseUserIsNil = Auth.auth().currentUser == nil
        let shouldSignOut = AccountDeletionAuthRacePolicy.shouldForceSignedOutOnGateRelease(
            firebaseCurrentUserIsNil: firebaseUserIsNil,
            deferredSignedOut: deferredSignedOutFromListener,
            accountDeletionFinalized: accountDeletionFinalized
        )
        deferredSignedOutFromListener = false
        guard shouldSignOut else { return }
        if case .signedOut = state {
            // Never auto-open AuthenticationView after account deletion.
            if accountDeletionFinalized {
                isPresentingAuthenticationSheet = false
            }
            #if DEBUG
            TodoshiDiagnostics.note(
                "[AccountDeletion] Auth currentUser=\(firebaseUserIsNil ? "nil" : "non-nil") instance=\(instanceID)"
            )
            #endif
            return
        }
        applySignedOutLocally(presentAuthenticationUI: false)
        if accountDeletionFinalized {
            isPresentingAuthenticationSheet = false
        }
        #if DEBUG
        TodoshiDiagnostics.note(
            "[AccountDeletion] Auth currentUser=\(firebaseUserIsNil ? "nil" : "non-nil") instance=\(instanceID)"
        )
        TodoshiDiagnostics.note("[AccountDeletion] Session state after=\(debugStateLabel(state))")
        #endif
    }

    private func finalizeAuthenticatedSession(
        preferredEmail: String?,
        preferredDisplayName: String? = nil
    ) async throws {
        guard let session = authService.currentSession() else {
            throw CollaborationError.invalidCredential
        }

        accountDeletionFinalized = false
        setAuthState(session)
        statusMessage = nil
        await runPostAuthenticationPipeline(
            for: session,
            preferredEmail: preferredEmail,
            preferredDisplayName: preferredDisplayName
        )

        if currentSession != nil {
            isPresentingAuthenticationSheet = false
        }
    }

    private func recoverAuthenticatedSessionAfterFailure(fallbackError: Error) async {
        if let session = authService.currentSession() {
            #if DEBUG
            TodoshiDiagnostics.note("[Auth] preserving authenticated session after secondary failure")
            #endif
            setAuthState(session)
            statusMessage = nil
            await runPostAuthenticationPipeline(
                for: session,
                preferredEmail: session.user.email
            )
            if currentSession != nil {
                isPresentingAuthenticationSheet = false
            }
            return
        }

        statusMessage = UserFacingError.message(for: fallbackError)
    }

    private func schedulePostAuthenticationPipeline(
        for session: CollaborationSession,
        preferredEmail: String?,
        preferredDisplayName: String? = nil
    ) {
        if let task = postAuthPipelineTask {
            task.cancel()
        }
        postAuthPipelineTask = Task { @MainActor in
            await self.runPostAuthenticationPipeline(
                for: session,
                preferredEmail: preferredEmail,
                preferredDisplayName: preferredDisplayName
            )
        }
    }

    private func runPostAuthenticationPipeline(
        for session: CollaborationSession,
        preferredEmail: String?,
        preferredDisplayName: String? = nil
    ) async {
        guard !Task.isCancelled else { return }
        await syncProfile(
            for: session,
            preferredEmail: preferredEmail,
            preferredDisplayName: preferredDisplayName
        )
        logIdentityPhase("profile sync finished")
        guard !Task.isCancelled else { return }
        await SharedProjectSyncService.shared.start(forUID: session.user.id)
        await ensureTodoshiIdentityProvisioned(for: session.user.id)
    }

    private func setAuthState(_ session: CollaborationSession?) {
        let old = state
        if let session {
            // Never restore signed-in from anything except a live Firebase user.
            if Auth.auth().currentUser == nil {
                #if DEBUG
                TodoshiDiagnostics.note(
                    "[AuthSession] refused signedIn without Firebase user instance=\(instanceID)"
                )
                #endif
                applySignedOutLocally(presentAuthenticationUI: false)
                return
            }
            state = .signedIn(session)
            logIdentityPhase("auth session ready")
        } else {
            SharedProjectSyncService.shared.stop()
            state = .signedOut
        }
        logStateTransition(from: old, to: state)
    }

    /// Authoritative local signed-out transition used by sign-out and account deletion.
    private func applySignedOutLocally(presentAuthenticationUI: Bool) {
        let old = state
        SharedProjectSyncService.shared.stop()
        state = .signedOut
        sessionUIEpoch &+= 1
        // Account deletion / sign-out: never auto-present AuthenticationView.
        // Manual `presentAuthenticationSheet()` remains available for collaboration gates.
        if presentAuthenticationUI {
            isPresentingAuthenticationSheet = true
        } else {
            isPresentingAuthenticationSheet = false
        }
        logStateTransition(from: old, to: state)
    }

    private func logStateTransition(from old: AuthenticationState, to new: AuthenticationState) {
        #if DEBUG
        TodoshiDiagnostics.note(
            "[AuthSession] STATE instance=\(instanceID) old=\(debugStateLabel(old)) new=\(debugStateLabel(new))"
        )
        #endif
    }

    private func debugStateLabel(_ state: AuthenticationState) -> String {
        switch state {
        case .loading: return "loading"
        case .signedOut: return "signedOut"
        case .signedIn: return "signedIn"
        }
    }

    private func syncProfile(
        for session: CollaborationSession,
        preferredEmail: String?,
        preferredDisplayName: String? = nil
    ) async {
        let resolvedDisplayName = CollaborationDisplayNamePolicy.normalized(session.user.displayName)
            ?? CollaborationDisplayNamePolicy.normalized(preferredDisplayName)
        do {
            try await profileService.syncProfile(
                uid: session.user.id,
                displayName: resolvedDisplayName,
                email: session.user.email ?? preferredEmail
            )
            profileSyncWarning = nil
        } catch {
            profileSyncWarning = UserFacingError.message(for: CollaborationError.profileSyncFailed)
            TodoshiDiagnostics.failure("profile_sync")
        }
    }

    private func ensureTodoshiIdentityProvisioned(for uid: String) async {
        guard authService.isConfigured else {
            logProvisionFailure(CollaborationError.notConfigured, phase: "configure")
            return
        }
        guard Auth.auth().currentUser != nil else {
            logProvisionFailure(CollaborationError.notAuthenticated, phase: "auth")
            return
        }

        if TodoshiIdentityProvisioningPolicy.normalized(cachedTodoshiID) != nil {
            clearProvisioningWarningIfNeeded()
            return
        }

        if let task = identityProvisionTask {
            await task.value
            if !TodoshiIdentitySessionPolicy.shouldRetryProvisioningAfterTask(
                cachedSessionTodoshiId: cachedTodoshiID
            ) {
                return
            }
            identityProvisionTask = nil
        }

        let task = Task { @MainActor in
            await performIdentityProvisioning(for: uid)
        }
        identityProvisionTask = task
        await task.value
        identityProvisionTask = nil
    }

    private func performIdentityProvisioning(for uid: String) async {
        logIdentityPhase("ensure started")
        do {
            let id = try await TodoshiIdentityService.shared.ensureProvisioned(uid: uid)
            publishIdentity(id)
            await refreshCanonicalProfile(uid: uid)
            logIdentityPhase("session refreshed")
        } catch {
            cachedTodoshiID = nil
            identityProvisioningWarning = UserFacingError.message(
                for: CollaborationError.identityProvisioningFailed
            )
            logProvisionFailure(error, phase: "ensure")
            TodoshiDiagnostics.failure("todoshi_identity")
        }
    }

    private func refreshCanonicalProfile(uid: String) async {
        do {
            let profile = try await profileService.loadProfile(uid: uid, preferServer: true)
            if let id = profile.todoshiId {
                publishIdentity(id)
            }
        } catch {
            clearProvisioningWarningIfNeeded()
        }
    }

    private func publishIdentity(_ todoshiId: String) {
        guard let normalized = TodoshiIdentityProvisioningPolicy.normalized(todoshiId) else { return }
        cachedTodoshiID = normalized
        clearProvisioningWarningIfNeeded()
        identityRevision &+= 1
    }

    private func clearProvisioningWarningIfNeeded() {
        if TodoshiIdentitySessionPolicy.shouldClearProvisioningWarning(sessionTodoshiId: cachedTodoshiID) {
            identityProvisioningWarning = nil
        }
    }

    private func logIdentityPhase(_ phase: String) {
        #if DEBUG
        TodoshiDiagnostics.note("[TodoshiID] \(phase)")
        #endif
    }

    #if DEBUG
    private func logProvisionFailure(_ error: Error, phase: String) {
        let info: FirestoreErrorPolicy.DebugInfo
        if let collaboration = error as? CollaborationError {
            let code: Int
            switch collaboration {
            case .notConfigured: code = 1
            case .notAuthenticated: code = 2
            case .identityProvisioningFailed: code = 3
            default: code = 0
            }
            info = FirestoreErrorPolicy.DebugInfo(
                domain: "TodoshiCore.CollaborationError",
                code: code,
                classification: .other
            )
        } else {
            info = FirestoreErrorPolicy.debugInfo(for: error)
        }
        TodoshiDiagnostics.note("[TodoshiID] provision failed")
        TodoshiDiagnostics.note("phase=\(phase)")
        TodoshiDiagnostics.note("domain=\(info.domain)")
        TodoshiDiagnostics.note("code=\(info.code)")
        TodoshiDiagnostics.note("classification=\(info.classification.rawValue)")
    }
    #else
    private func logProvisionFailure(_ error: Error, phase: String) {}
    #endif
}
