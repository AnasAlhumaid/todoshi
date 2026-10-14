import SwiftUI
import TodoshiCore

struct ProjectMembersView: View {
    let projectID: UUID
    let projectName: String

    @Environment(AuthSessionController.self) private var authSession

    @State private var members: [ProjectMemberRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var listenerToken: UUID?
    @State private var currentRole: ProjectMemberRole?
    @State private var isCreatingInvite = false
    @State private var sharePayload: ShareInvitePayload?
    @State private var actionError: String?

    var body: some View {
        Group {
            if isLoading && members.isEmpty {
                ProgressView(TodoshiL10n.tr("project.share.progress"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, members.isEmpty {
                ContentUnavailableView {
                    Label(TodoshiL10n.tr("common.somethingWrong"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(TodoshiL10n.tr("common.retry")) {
                        restartListener()
                    }
                    .frame(minHeight: TodoshiIconSize.hit)
                }
            } else if members.isEmpty {
                ContentUnavailableView(
                    TodoshiL10n.tr("project.members.empty"),
                    systemImage: SharedProjectPresentation.indicatorSystemImage
                )
            } else {
                List {
                    ForEach(members) { member in
                        NavigationLink {
                            ProjectMemberDetailView(
                                projectID: projectID,
                                memberUserId: member.userId,
                                members: members,
                                isOwnerViewer: currentRole == .owner
                            )
                        } label: {
                            memberRow(member)
                        }
                    }
                    if SharedProjectRolePermissions.canInviteMembers(role: currentRole) {
                        Section {
                            Button {
                                Task { await createInvite() }
                            } label: {
                                Label(
                                    TodoshiL10n.tr("project.invite.member"),
                                    systemImage: "person.badge.plus"
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: TodoshiIconSize.hit)
                            }
                            .disabled(isCreatingInvite)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(TodoshiL10n.tr("project.members.title"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isCreatingInvite {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView()
                        .padding(TodoshiSpacing.lg)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: TodoshiRadius.md))
                }
            }
        }
        .alert(
            TodoshiL10n.tr("common.somethingWrong"),
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button(TodoshiL10n.tr("common.ok"), role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .sheet(item: $sharePayload) { payload in
            ActivityShareSheet(activityItems: [payload.shareMessage])
        }
        .onAppear { restartListener() }
        .onDisappear {
            SharedProjectMembersService.shared.stopListening(listenerToken)
            listenerToken = nil
        }
    }

    @ViewBuilder
    private func memberRow(_ member: ProjectMemberRow) -> some View {
        let name = displayName(for: member)
        HStack(spacing: TodoshiSpacing.sm) {
            avatar(for: name)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.medium))
                Text(SharedProjectPresentation.memberRoleLabel(member.role))
                    .font(TodoshiTypography.metadata)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(SharedProjectPresentation.memberRoleLabel(member.role))")
    }

    private func displayName(for member: ProjectMemberRow) -> String {
        let trimmed = member.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return TodoshiL10n.tr("project.members.unnamed")
        }
        return trimmed
    }

    @ViewBuilder
    private func avatar(for name: String) -> some View {
        TodoshiAvatar(displayName: name, size: 40)
    }

    private func restartListener() {
        SharedProjectMembersService.shared.stopListening(listenerToken)
        listenerToken = nil
        isLoading = members.isEmpty
        errorMessage = nil

        let uid = authSession.currentSession?.user.id
        listenerToken = SharedProjectMembersService.shared.startListening(
            projectID: projectID,
            onChange: { rows in
                Task { @MainActor in
                    members = rows
                    if let uid {
                        let role = rows.first(where: { $0.userId == uid })?.role
                        if currentRole != nil, role == nil, rows.allSatisfy({ $0.userId != uid }) {
                            await SharedProjectSyncService.shared.evictSharedProjectAfterDeparture(
                                projectID: projectID,
                                voluntary: false
                            )
                        }
                        currentRole = role
                    }
                    isLoading = false
                    errorMessage = nil
                }
            },
            onError: { error in
                Task { @MainActor in
                    if members.isEmpty {
                        errorMessage = UserFacingError.message(for: error)
                    }
                    isLoading = false
                }
            }
        )
    }

    private func createInvite() async {
        guard !isCreatingInvite else { return }
        guard SharedProjectRolePermissions.canInviteMembers(role: currentRole) else {
            actionError = UserFacingError.message(for: CollaborationError.inviteNotOwner)
            return
        }
        isCreatingInvite = true
        defer { isCreatingInvite = false }

        do {
            let created = try await ProjectInviteService.shared.createInvite(
                projectID: projectID,
                projectTitle: projectName,
                inviterDisplayName: authSession.currentSession?.user.displayName
            )
            sharePayload = ShareInvitePayload(shareMessage: created.shareMessage)
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }
}

private struct ShareInvitePayload: Identifiable {
    let id = UUID()
    let shareMessage: String
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
