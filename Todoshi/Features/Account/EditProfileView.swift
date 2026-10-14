import SwiftUI
import TodoshiCore

struct EditProfileView: View {
    @Environment(AuthSessionController.self) private var authSession
    @Environment(\.dismiss) private var dismiss

    let profile: CollaborationProfile
    @Bindable var controller: ProfileController

    @State private var displayName: String

    init(profile: CollaborationProfile, controller: ProfileController) {
        self.profile = profile
        self.controller = controller
        _displayName = State(initialValue: profile.displayName ?? "")
    }

    var body: some View {
        Form {
            Section {
                ProfileAvatarView(displayName: displayName, isLoading: false, size: 96)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            Section(ProfileStrings.displayName) {
                TextField(ProfileStrings.displayName, text: $displayName)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .accessibilityLabel(ProfileStrings.displayName)
            }

            Section(ProfileStrings.email) {
                Text(profile.email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                     ?? TodoshiL10n.tr("account.defaultLabel"))
                    .foregroundStyle(.secondary)
            }

            if let message = controller.statusMessage {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(ProfileStrings.edit)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if controller.isSaving {
                    ProgressView()
                } else {
                    Button(ProfileStrings.save) {
                        Task { await save() }
                    }
                    .disabled(controller.isSaving)
                }
            }
        }
    }

    private func save() async {
        guard let uid = authSession.currentSession?.user.id else { return }
        let ok = await controller.save(uid: uid, displayNameRaw: displayName)
        if ok {
            if let name = controller.profile?.displayName {
                authSession.applyDisplayNameUpdate(name)
            }
            dismiss()
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
