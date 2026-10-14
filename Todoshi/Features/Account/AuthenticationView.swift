import AuthenticationServices
import SwiftUI
import TodoshiCore

struct AuthenticationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthSessionController.self) private var authSession

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: TodoshiSpacing.md) {
                    TodoshiLogoMark(size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        TodoshiWordmark(size: .title2.weight(.bold))
                        Text(TodoshiL10n.tr("account.sheet.message"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                AuthProviderButtons(
                    isSigningIn: authSession.isSigningIn,
                    onAppleSuccess: { authorization in
                        await authSession.handleAppleAuthorization(authorization)
                        if authSession.currentSession != nil {
                            dismiss()
                        }
                    },
                    onAppleFailure: { error in
                        await authSession.handleAppleAuthorizationFailure(error)
                    },
                    onGoogle: {
                        await authSession.signInWithGoogle()
                        if authSession.currentSession != nil {
                            dismiss()
                        }
                    }
                )

                if let message = authSession.statusMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(AccountStrings.section)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(TodoshiL10n.tr("common.cancel")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
