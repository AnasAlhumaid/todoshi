import SwiftUI
import SwiftData
import TodoshiCore

/// Invite preview / join sheet for `todoshi://invite/<token>`.
struct ProjectInvitePreviewView: View {
    let token: String

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSessionController.self) private var authSession
    @Environment(AppRouter.self) private var router

    @State private var preview: ProjectInvitePreview?
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(TodoshiL10n.tr("project.invite.loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let statusMessage {
                    ContentUnavailableView {
                        Label(TodoshiL10n.tr("project.invite.previewTitle"), systemImage: "link.badge.plus")
                    } description: {
                        Text(statusMessage)
                    } actions: {
                        Button(TodoshiL10n.tr("common.ok")) { router.dismissInvitePreview() }
                            .frame(minHeight: TodoshiIconSize.hit)
                    }
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label(TodoshiL10n.tr("common.somethingWrong"), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button(TodoshiL10n.tr("common.retry")) {
                            Task { await load() }
                        }
                        .frame(minHeight: TodoshiIconSize.hit)
                        Button(TodoshiL10n.tr("common.cancel"), role: .cancel) { router.dismissInvitePreview() }
                            .frame(minHeight: TodoshiIconSize.hit)
                    }
                } else if let preview {
                    previewContent(preview)
                }
            }
            .navigationTitle(TodoshiL10n.tr("project.invite.previewTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(TodoshiL10n.tr("common.cancel")) {
                        router.dismissInvitePreview()
                    }
                }
            }
            .overlay {
                if isJoining {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        ProgressView(TodoshiL10n.tr("project.invite.joining"))
                            .padding(TodoshiSpacing.lg)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: TodoshiRadius.md))
                    }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func previewContent(_ preview: ProjectInvitePreview) -> some View {
        VStack(spacing: TodoshiSpacing.lg) {
            Spacer(minLength: TodoshiSpacing.md)
            Image(systemName: SharedProjectPresentation.indicatorSystemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(preview.projectTitle)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(inviteBody(for: preview))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TodoshiSpacing.lg)
            Spacer()
            Button {
                Task { await join(preview) }
            } label: {
                Text(TodoshiL10n.tr("project.invite.join"))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: TodoshiIconSize.hit)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isJoining)
            .padding(.horizontal, TodoshiSpacing.lg)
            Button(TodoshiL10n.tr("common.cancel"), role: .cancel) { router.dismissInvitePreview() }
                .frame(minHeight: TodoshiIconSize.hit)
                .padding(.bottom, TodoshiSpacing.lg)
        }
        .padding()
    }

    private func inviteBody(for preview: ProjectInvitePreview) -> String {
        let name = preview.inviterDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.isEmpty {
            return TodoshiL10n.tr("project.invite.previewMessageAnonymous")
        }
        return TodoshiL10n.format("project.invite.previewMessage", name)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        defer { isLoading = false }

        do {
            let loaded = try await ProjectInviteService.shared.fetchPreview(token: token)
            switch loaded.status {
            case .valid:
                preview = loaded
            case .expired, .accepted, .revoked, .invalid:
                statusMessage = ProjectInviteStatusPolicy.userMessage(for: loaded.status)
                preview = nil
            }
        } catch {
            errorMessage = UserFacingError.message(for: error)
            preview = nil
        }
    }

    private func join(_ preview: ProjectInvitePreview) async {
        guard !isJoining else { return }
        guard await authSession.ensureCollaborationIdentityReady() else {
            errorMessage = authSession.identityProvisioningWarning
                ?? UserFacingError.message(for: CollaborationError.identityProvisioningFailed)
            return
        }
        isJoining = true
        defer { isJoining = false }

        do {
            let result = try await ProjectInviteService.shared.acceptInvite(
                token: token,
                displayName: authSession.currentSession?.user.displayName
            )
            let meta: JoinedProjectRemoteMetadata
            switch result {
            case .joined(let m), .alreadyMember(let m):
                meta = m
            }
            let shell = JoinedSharedProjectShellPolicy.make(
                projectID: meta.projectID,
                title: meta.title,
                description: meta.description,
                color: meta.color,
                projectType: meta.projectType
            )
            _ = try ProjectRepository(context: modelContext).upsertJoinedSharedProjectShell(
                shell,
                collaborationOwnerUID: authSession.currentSession?.user.id
            )
            if let uid = authSession.currentSession?.user.id {
                await SharedProjectSyncService.shared.start(forUID: uid)
            }
            router.dismissInvitePreview()
            router.open(.project(meta.projectID))
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
