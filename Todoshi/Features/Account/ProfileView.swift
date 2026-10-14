import SwiftUI
import SwiftData
import TodoshiCore

enum ProfileStrings {
    static var title: String { TodoshiL10n.tr("profile.title") }
    static var edit: String { TodoshiL10n.tr("profile.edit") }
    static var displayName: String { TodoshiL10n.tr("profile.displayName") }
    static var email: String { TodoshiL10n.tr("profile.email") }
    static var save: String { TodoshiL10n.tr("profile.save") }
    static var signOut: String { TodoshiL10n.tr("account.signOut") }
    static var deleteAccount: String { TodoshiL10n.tr("account.delete.title") }
    static var openAccessibility: String { TodoshiL10n.tr("profile.openAccessibility") }
    static var avatarAccessibility: String { TodoshiL10n.tr("profile.avatarAccessibility") }
    static var unavailable: String { TodoshiL10n.tr("profile.unavailable") }
    static var defaultAccountLabel: String { TodoshiL10n.tr("account.defaultLabel") }
    static var nameCompletionTitle: String { TodoshiL10n.tr("profile.nameCompletion.title") }
    static var nameCompletionMessage: String { TodoshiL10n.tr("profile.nameCompletion.message") }
    static var todoshiIdLabel: String { TodoshiL10n.tr("identity.todoshiId.label") }
    static var todoshiIdHint: String { TodoshiL10n.tr("identity.todoshiId.hint") }
}

struct ProfileView: View {
    @Environment(AuthSessionController.self) private var authSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var controller = ProfileController()
    @State private var deletionController = AccountDeletionController()
    @State private var showDeleteConfirm = false
    @State private var showDeletionError = false

    private var profileForEditing: CollaborationProfile {
        controller.profile ?? CollaborationProfile(
            userID: authSession.currentSession?.user.id ?? "",
            displayName: authSession.currentSession?.user.displayName,
            email: authSession.currentSession?.user.email
        )
    }

    var body: some View {
        Group {
            if case .signedIn(let session) = authSession.state {
                content(session: session)
            } else {
                ContentUnavailableView {
                    Label(ProfileStrings.title, systemImage: "person.crop.circle")
                } description: {
                    Text(TodoshiL10n.tr("account.error.notSignedIn"))
                }
            }
        }
        .navigationTitle(ProfileStrings.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            TodoshiL10n.tr("account.delete.confirmTitle"),
            isPresented: $showDeleteConfirm
        ) {
            Button(TodoshiL10n.tr("account.delete.cancel"), role: .cancel) {}
            Button(TodoshiL10n.tr("account.delete.title"), role: .destructive) {
                #if DEBUG
                TodoshiDiagnostics.note("[AccountDeletionUI] destructive confirm tapped")
                #endif
                startClientDeletion()
            }
        } message: {
            Text(TodoshiL10n.tr("account.delete.confirmMessage"))
        }
        .alert(
            TodoshiL10n.tr(deletionController.errorTitleKey),
            isPresented: $showDeletionError
        ) {
            Button(TodoshiL10n.tr("account.delete.cancel"), role: .cancel) {
                deletionController.reset()
            }
            Button(TodoshiL10n.tr("account.delete.retry"), role: .destructive) {
                startClientDeletion()
            }
        } message: {
            Text(deletionController.errorMessage ?? TodoshiL10n.tr("account.delete.error"))
        }
        .onChange(of: deletionController.phase) { _, phase in
            if phase == .failed {
                showDeletionError = deletionController.errorMessage != nil
            }
        }
        .onChange(of: authSession.state) { _, newState in
            guard case .signedOut = newState else { return }
            controller = ProfileController()
            deletionController.reset()
            #if DEBUG
            TodoshiDiagnostics.note("[AccountDeletionUI] Settings root")
            #endif
            dismiss()
        }
        .onAppear {
            #if DEBUG
            let label: String
            switch authSession.state {
            case .loading: label = "loading"
            case .signedOut: label = "signedOut"
            case .signedIn: label = "signedIn"
            }
            TodoshiDiagnostics.note("[Profile] authInstance=\(authSession.instanceID) state=\(label)")
            #endif
        }
        .task(id: profileRefreshToken) {
            guard let uid = authSession.currentSession?.user.id else { return }
            if let session = authSession.currentSession {
                controller.applySessionFallback(session)
            }
            if let cached = authSession.cachedTodoshiID {
                controller.applyTodoshiID(cached)
            }
            await controller.load(uid: uid)
            if TodoshiIdentitySessionPolicy.shouldReloadProfile(
                profileTodoshiId: controller.profile?.todoshiId,
                sessionTodoshiId: authSession.cachedTodoshiID
            ) {
                controller.applyTodoshiID(authSession.cachedTodoshiID)
            }
            if controller.profile?.todoshiId == nil {
                _ = await authSession.ensureCollaborationIdentityReady()
            }
            if let cached = authSession.cachedTodoshiID {
                controller.applyTodoshiID(cached)
            }
            await controller.load(uid: uid, preferServer: authSession.cachedTodoshiID != nil)
            if let name = controller.profile?.displayName {
                authSession.applyDisplayNameUpdate(name)
            }
        }
    }

    @ViewBuilder
    private func content(session: CollaborationSession) -> some View {
        List {
            Section {
                VStack(spacing: 16) {
                    TodoshiAvatar(
                        displayName: controller.profile?.displayName ?? session.user.displayName,
                        size: 96,
                        isLoading: controller.loadState == .loading
                    )
                    .frame(maxWidth: .infinity)

                    identityBlock(for: controller.profile ?? CollaborationProfile(
                        userID: session.user.id,
                        displayName: session.user.displayName,
                        email: session.user.email
                    ))
                }
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            if controller.loadState == .unavailable {
                Section {
                    Text(controller.statusMessage ?? ProfileStrings.unavailable)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let identityWarning = authSession.identityProvisioningWarning,
               authSession.cachedTodoshiID == nil {
                Section {
                    Text(identityWarning)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if needsNameCompletion(session: session) {
                Section {
                    VStack(alignment: .leading, spacing: TodoshiSpacing.xs) {
                        Text(ProfileStrings.nameCompletionTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(ProfileStrings.nameCompletionMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        NavigationLink {
                            EditProfileView(profile: profileForEditing, controller: controller)
                        } label: {
                            Text(ProfileStrings.edit)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .padding(.vertical, TodoshiSpacing.xxs)
                }
            }

            Section {
                NavigationLink {
                    EditProfileView(profile: profileForEditing, controller: controller)
                } label: {
                    Text(ProfileStrings.edit)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .disabled(controller.profile == nil && controller.loadState != .loaded)
            }

            Section {
                Button(role: .destructive) {
                    Task {
                        await authSession.signOut()
                        dismiss()
                    }
                } label: {
                    Text(ProfileStrings.signOut)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                }
                .disabled(authSession.isSigningIn || controller.isSaving || deletionController.isDeleting)
            }

            Section {
                if deletionController.isDeleting {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(TodoshiL10n.tr("account.delete.progress"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
                    .accessibilityIdentifier("accountDeletionInlineProgress")
                } else {
                    Button(role: .destructive) {
                        #if DEBUG
                        TodoshiDiagnostics.note("[AccountDeletionUI] Profile delete tapped")
                        #endif
                        deletionController.reset()
                        showDeleteConfirm = true
                    } label: {
                        Text(ProfileStrings.deleteAccount)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
                            .foregroundStyle(.red)
                    }
                    .disabled(authSession.isSigningIn || controller.isSaving)
                    .listRowBackground(Color.red.opacity(0.08))
                }
            } footer: {
                Text(TodoshiL10n.tr("account.delete.footer"))
                    .font(.footnote)
            }
        }
        .listStyle(.insetGrouped)
    }

    @MainActor
    private func startClientDeletion() {
        let session = authSession
        deletionController.deleteAccountWithoutReauthentication(
            modelContext: modelContext,
            uid: session.currentSession?.user.id,
            onAuthDeletionGate: { session.setAccountDeletionInProgress($0) },
            onFinalizeSession: {
                session.applyAccountDeletedLocally()
            },
            onFinished: {
                #if DEBUG
                TodoshiDiagnostics.note("[AccountDeletionUI] Settings root")
                #endif
            }
        )
    }

    private func identityBlock(for profile: CollaborationProfile) -> some View {
        let lines = ProfileIdentityPresentation.lines(
            displayName: profile.displayName,
            email: profile.email,
            fallback: ProfileStrings.defaultAccountLabel
        )
        let todoshiID = resolvedTodoshiID(for: profile)
        return VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(lines.primary)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let secondary = lines.secondary {
                    Text(secondary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            if TodoshiIdentityPresentationPolicy.showsOwnTodoshiIDInProfile(isSignedIn: true),
               let todoshiID {
                VStack(spacing: 4) {
                    Text(ProfileStrings.todoshiIdLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(todoshiID)
                        .font(.system(.subheadline, design: .monospaced))
                        .textSelection(.enabled)
                    Text(ProfileStrings.todoshiIdHint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(ProfileStrings.todoshiIdLabel), \(TodoshiIDPolicy.accessibilitySpoken(todoshiID))"
                )
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var profileRefreshToken: String {
        let uid = authSession.currentSession?.user.id ?? ""
        return "\(uid)-\(authSession.identityRevision)"
    }

    private func resolvedTodoshiID(for profile: CollaborationProfile) -> String? {
        TodoshiIdentitySessionPolicy.resolvedTodoshiId(
            profileTodoshiId: profile.todoshiId,
            sessionTodoshiId: authSession.cachedTodoshiID
        )
    }

    private func needsNameCompletion(session: CollaborationSession) -> Bool {
        ProfileDisplayNameCompletionPolicy.needsCompletion(
            profileName: controller.profile?.displayName,
            authName: session.user.displayName
        )
    }
}

struct ProfileAvatarView: View {
    let displayName: String?
    let isLoading: Bool
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: size, height: size)

            placeholder

            if isLoading {
                ProgressView()
            }
        }
        .accessibilityLabel(ProfileStrings.avatarAccessibility)
        .accessibilityAddTraits(.isImage)
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder
    private var placeholder: some View {
        let initials = ProfileAvatarInitialsPolicy.initials(from: displayName)
        if initials.isEmpty {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.55, height: size * 0.55)
                .foregroundStyle(.secondary)
        } else {
            Text(initials)
                .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
    }
}
