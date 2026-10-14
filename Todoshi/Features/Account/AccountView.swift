import AuthenticationServices
import SwiftUI
import TodoshiCore

enum AccountStrings {
    static var section: String { TodoshiL10n.tr("account.section") }
    static var signedOutDescription: String { TodoshiL10n.tr("account.signedOutDescription") }
    static var signInWithApple: String { TodoshiL10n.tr("account.signInWithApple") }
    static var continueWithGoogle: String { TodoshiL10n.tr("account.continueWithGoogle") }
    static var signOut: String { TodoshiL10n.tr("account.signOut") }
    static var unavailable: String { TodoshiL10n.tr("account.unavailable") }
    static var defaultAccountLabel: String { TodoshiL10n.tr("account.defaultLabel") }
    static var profileSyncWarning: String { TodoshiL10n.tr("account.profileSyncWarning") }
    static var testAuthenticationSheet: String { TodoshiL10n.tr("account.testAuthenticationSheet") }
    static var openProfile: String { TodoshiL10n.tr("profile.openAccessibility") }
}

struct AccountView: View {
    @Environment(AuthSessionController.self) private var authSession

    var body: some View {
        Section {
            switch authSession.configurationStatus {
            case .configuredLocalOnly:
                Text(AccountStrings.unavailable)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .configuredWithBackend:
                accountContent
            case .unavailable:
                Text(AccountStrings.unavailable)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(AccountStrings.section)
        }
    }

    @ViewBuilder
    private var accountContent: some View {
        switch RootAuthPresentationPolicy.accountChrome(for: authSession.state) {
        case .loading:
            ProgressView()
        case .signInPrompt:
            signedOutContent
        case .authenticatedAccount:
            if case .signedIn(let session) = authSession.state {
                NavigationLink {
                    ProfileView()
                } label: {
                    signedInRow(session: session)
                }
                .accessibilityLabel(AccountStrings.openProfile)
            } else {
                signedOutContent
            }
        }

        if let warning = authSession.profileSyncWarning {
            Text(warning)
                .font(.footnote)
                .foregroundStyle(.orange)
        }

        if let message = authSession.statusMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        #if DEBUG
        Button(AccountStrings.testAuthenticationSheet) {
            authSession.presentAuthenticationSheet()
        }
        .font(.footnote)
        #endif
    }

    private var signedOutContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AccountStrings.signedOutDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            AuthProviderButtons(
                isSigningIn: authSession.isSigningIn,
                onAppleSuccess: { authorization in
                    await authSession.handleAppleAuthorization(authorization)
                },
                onAppleFailure: { error in
                    await authSession.handleAppleAuthorizationFailure(error)
                },
                onGoogle: {
                    await authSession.signInWithGoogle()
                }
            )
        }
        .padding(.vertical, 4)
    }

    private func signedInRow(session: CollaborationSession) -> some View {
        let lines = ProfileIdentityPresentation.lines(
            displayName: session.user.displayName,
            email: session.user.email,
            fallback: AccountStrings.defaultAccountLabel
        )
        return VStack(alignment: .leading, spacing: 2) {
            Text(lines.primary)
                .font(.headline)
            if let secondary = lines.secondary {
                Text(secondary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct AuthProviderButtons: View {
    let isSigningIn: Bool
    let onAppleSuccess: (ASAuthorization) async -> Void
    let onAppleFailure: (Error) async -> Void
    let onGoogle: () async -> Void

    @Environment(AuthSessionController.self) private var authSession

    var body: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn) { request in
                authSession.configureAppleSignInRequest(request)
            } onCompletion: { result in
                Task {
                    switch result {
                    case .success(let authorization):
                        await onAppleSuccess(authorization)
                    case .failure(let error):
                        await onAppleFailure(error)
                    }
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .disabled(isSigningIn)
            .accessibilityLabel(AccountStrings.signInWithApple)

            Button {
                Task { await onGoogle() }
            } label: {
                Text(AccountStrings.continueWithGoogle)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(isSigningIn)
            .accessibilityLabel(AccountStrings.continueWithGoogle)

            if isSigningIn {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(TodoshiL10n.tr("account.signingIn"))
            }
        }
    }
}
