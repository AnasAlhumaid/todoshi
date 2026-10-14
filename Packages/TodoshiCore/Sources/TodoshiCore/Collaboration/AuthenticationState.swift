import Foundation

public enum AuthenticationState: Sendable, Equatable {
    case loading
    case signedOut
    case signedIn(CollaborationSession)
}

public enum CollaborationAuthRequirement: Sendable, Equatable {
    case authenticated(CollaborationSession)
    case requiresAuthentication
}

public enum CollaborationAuthGate: Sendable {
    public static func requirement(for session: CollaborationSession?) -> CollaborationAuthRequirement {
        if let session {
            return .authenticated(session)
        }
        return .requiresAuthentication
    }
}

/// Top-level / Settings presentation decisions driven only by AuthSessionController state.
public enum RootAuthPresentationPolicy: Sendable {
    public enum Chrome: String, Sendable, Equatable {
        case authenticatedAccount
        case signInPrompt
        case loading
    }

    /// Settings Account section chrome from authoritative session state only.
    public static func accountChrome(for state: AuthenticationState) -> Chrome {
        switch state {
        case .loading:
            return .loading
        case .signedOut:
            return .signInPrompt
        case .signedIn:
            return .authenticatedAccount
        }
    }

    /// After account deletion, do NOT auto-present `AuthenticationView`.
    /// Settings root already shows the signed-out Sign In account section.
    public static func shouldPresentAuthenticationUI(
        state: AuthenticationState,
        accountDeletionFinalized: Bool
    ) -> Bool {
        _ = state
        _ = accountDeletionFinalized
        return false
    }

    /// Explicit product rule: deletion finalization keeps the auth sheet closed.
    public static func keepsAuthenticationSheetClosedAfterAccountDeletion() -> Bool { true }

    /// Manual Sign In / collaboration gate may still open AuthenticationView later.
    public static func allowsManualAuthenticationSheetAfterDeletion() -> Bool { true }

    /// Profile push must be destroyed when returning to Settings after deletion.
    public static func destroysProfileNavigationAfterAccountDeletion() -> Bool { true }

    /// Terminal routing: Settings root + signed-out chrome (not auth sheet).
    public static func terminalDestinationAfterAccountDeletion() -> Chrome {
        .signInPrompt
    }

    /// Provider used for Delete Account reauth must match the Firebase account.
    public static func reauthProvider(
        for resolved: AccountDeletionAuthProvider
    ) -> AccountDeletionAuthProvider {
        resolved
    }

    /// Signed-out must tear down authenticated navigation (Profile stack, etc.).
    public static func shouldResetAuthenticatedNavigation(for state: AuthenticationState) -> Bool {
        if case .signedOut = state { return true }
        return false
    }

    /// Firebase Auth is sole authority — local profile/cache cannot restore signed-in.
    public static func canRestoreSignedInFromLocalProfile(
        firebaseCurrentUserIsNil: Bool,
        hasStaleLocalProfile: Bool
    ) -> Bool {
        _ = hasStaleLocalProfile
        return !firebaseCurrentUserIsNil
    }

    /// Settings/Profile must not keep authenticated chrome after signedOut.
    public static func retainsAuthenticatedSettingsUI(after state: AuthenticationState) -> Bool {
        if case .signedIn = state { return true }
        return false
    }

    /// Same controller instance must back deletion + root UI.
    public static func isSameAuthSessionInstance(
        rootInstanceID: ObjectIdentifier,
        deletionInstanceID: ObjectIdentifier
    ) -> Bool {
        rootInstanceID == deletionInstanceID
    }
}

/// Single terminal routing result after successful account deletion.
public enum AccountDeletionTerminalPresentationPolicy: Sendable {
    public enum DestinationTab: String, Sendable, Equatable {
        case settings
    }

    /// AD-74: AccountDeletion sheet binding must close on terminal success.
    public static func closesAccountDeletionSheet(terminalSuccess: Bool) -> Bool {
        terminalSuccess
    }

    /// AD-75: Profile push must be destroyed (Settings stack rebuilt / popped).
    public static func closesProfileNavigation(terminalSuccess: Bool) -> Bool {
        terminalSuccess
    }

    /// AD-76: Never auto-present AuthenticationView after deletion.
    public static func presentsAuthenticationSheet(terminalSuccess: Bool) -> Bool {
        _ = terminalSuccess
        return false
    }

    /// AD-77: Selected tab after deletion is Settings.
    public static func selectedTabAfterDeletion() -> DestinationTab {
        .settings
    }

    public static func selectsSettingsTab(terminalSuccess: Bool) -> Bool {
        terminalSuccess && selectedTabAfterDeletion() == .settings
    }

    /// AD-78: Settings root shows inline Sign In when signedOut.
    public static func settingsRootChrome(for state: AuthenticationState) -> RootAuthPresentationPolicy.Chrome {
        RootAuthPresentationPolicy.accountChrome(for: state)
    }

    /// AD-79: Force quit / relaunch with no Firebase user remains signedOut + Sign In.
    public static func remainsSignedOutAfterRelaunch(firebaseCurrentUserIsNil: Bool) -> Bool {
        firebaseCurrentUserIsNil
    }

    public static func authenticationSheetBinding(
        isPresentingAuthenticationSheet: Bool,
        terminalSuccess: Bool
    ) -> Bool {
        if terminalSuccess { return false }
        return isPresentingAuthenticationSheet
    }

    public static func accountDeletionSheetBinding(
        showDeleteAccount: Bool,
        terminalSuccess: Bool
    ) -> Bool {
        if terminalSuccess { return false }
        return showDeleteAccount
    }

    /// Authoritative terminal snapshot — one routing result only.
    public static func terminalSnapshot(
        authState: AuthenticationState,
        isPresentingAuthenticationSheet: Bool,
        showDeleteAccount: Bool,
        selectedTabIsSettings: Bool,
        profileNavigationRetained: Bool
    ) -> Bool {
        guard case .signedOut = authState else { return false }
        guard !isPresentingAuthenticationSheet else { return false }
        guard !showDeleteAccount else { return false }
        guard selectedTabIsSettings else { return false }
        guard !profileNavigationRetained else { return false }
        guard settingsRootChrome(for: authState) == .signInPrompt else { return false }
        return true
    }
}
