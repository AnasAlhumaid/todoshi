import SwiftUI
import TodoshiCore

/// Realtime Firestore comments for a shared task. Listener lives only while this section is on-screen.
struct TaskDetailCommentsSection: View {
    let projectID: UUID
    let taskID: UUID
    let isTaskSoftDeleted: Bool
    var embedInList: Bool = true
    var showsSectionHeader: Bool = true
    var onError: (String) -> Void

    @Environment(AuthSessionController.self) private var authSession

    @State private var comments: [TaskComment] = []
    @State private var members: [AssignmentCandidate] = []
    @State private var draft = ""
    @State private var viewerRole: ProjectMemberRole?
    @State private var listenerToken: UUID?
    @State private var isPosting = false
    @State private var editingComment: TaskComment?
    @State private var editingBody = ""
    @State private var commentPendingDelete: TaskComment?
    @FocusState private var isComposerFocused: Bool

    private var currentUID: String? {
        authSession.currentSession?.user.id
    }

    var canCompose: Bool {
        !isTaskSoftDeleted
            && SharedProjectRolePermissions.canCreateComments(role: viewerRole)
            && currentUID != nil
            && TaskCommentService.shared.isConfigured
    }

    var commentCount: Int { comments.count }

    var body: some View {
        Group {
            if embedInList {
                listEmbeddedBody
            } else {
                standaloneBody
            }
        }
        .task(id: "\(projectID.uuidString)-\(taskID.uuidString)") {
            await start()
        }
        .onDisappear {
            stop()
        }
        .alert(TaskCommentStrings.editTitle, isPresented: Binding(
            get: { editingComment != nil },
            set: { if !$0 { editingComment = nil } }
        )) {
            TextField(TaskCommentStrings.placeholder, text: $editingBody, axis: .vertical)
            Button(TodoshiL10n.tr("common.save")) {
                Task { await saveEdit() }
            }
            Button(TodoshiL10n.tr("common.cancel"), role: .cancel) {
                editingComment = nil
            }
        }
        .confirmationDialog(
            TaskCommentStrings.deleteConfirm,
            isPresented: Binding(
                get: { commentPendingDelete != nil },
                set: { if !$0 { commentPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(TodoshiL10n.tr("common.delete"), role: .destructive) {
                Task { await confirmDelete() }
            }
            Button(TodoshiL10n.tr("common.cancel"), role: .cancel) {
                commentPendingDelete = nil
            }
        }
    }

    @ViewBuilder
    private var listEmbeddedBody: some View {
        Section {
            commentsContent
            if canCompose {
                composerField
            }
        } header: {
            if showsSectionHeader {
                Text(TaskCommentStrings.comments)
            }
        }
    }

    @ViewBuilder
    private var standaloneBody: some View {
        VStack(alignment: .leading, spacing: TodoshiSpacing.sm) {
            commentsContent
        }
    }

    @ViewBuilder
    private var commentsContent: some View {
        if comments.isEmpty {
            Text(TaskCommentStrings.empty)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, TodoshiSpacing.xs)
        } else {
            ForEach(comments) { comment in
                commentRow(comment)
            }
        }
    }

    /// Composer for safe-area inset or inline list use.
    var composerBar: some View {
        Group {
            if canCompose {
                composerField
                    .padding(.horizontal, TodoshiSpacing.md)
                    .padding(.vertical, TodoshiSpacing.sm)
                    .background(.bar)
            }
        }
    }

    private var composerField: some View {
        HStack(alignment: .bottom, spacing: TodoshiSpacing.sm) {
            TextField(TaskCommentStrings.placeholder, text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($isComposerFocused)
                .submitLabel(.send)
                .onSubmit { Task { await post() } }
                .padding(.horizontal, TodoshiSpacing.sm)
                .padding(.vertical, TodoshiSpacing.xs)
                .background(TodoshiBrand.elevatedSurface, in: RoundedRectangle(cornerRadius: TodoshiRadius.lg, style: .continuous))

            Button {
                Task { await post() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? TodoshiBrand.accent.opacity(0.35)
                            : TodoshiBrand.accent
                    )
            }
            .disabled(isPosting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .frame(width: TodoshiIconSize.hit, height: TodoshiIconSize.hit)
            .accessibilityLabel(TaskCommentStrings.send)
        }
    }

    @ViewBuilder
    private func commentRow(_ comment: TaskComment) -> some View {
        let uid = currentUID
        let canEdit = TaskCommentModerationPolicy.canEditBody(
            viewerUID: uid,
            commentAuthorUID: comment.authorUID
        )
        let canDelete = TaskCommentModerationPolicy.canSoftDelete(
            viewerUID: uid,
            viewerRole: viewerRole,
            commentAuthorUID: comment.authorUID
        )
        let authorName = CommentAuthorPresentation.displayName(
            authorUID: comment.authorUID,
            storedName: comment.authorDisplayName,
            members: members
        )

        HStack(alignment: .top, spacing: TodoshiSpacing.sm) {
            TodoshiAvatar(displayName: authorName, size: 36)

            VStack(alignment: .leading, spacing: TodoshiSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: TodoshiSpacing.xs) {
                    Text(authorName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(comment.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(comment.body)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if canEdit || canDelete {
                    HStack(spacing: TodoshiSpacing.md) {
                        if canEdit {
                            Button(TodoshiL10n.tr("common.edit")) {
                                editingComment = comment
                                editingBody = comment.body
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TodoshiBrand.accent)
                        }
                        if canDelete {
                            Button(TodoshiL10n.tr("common.delete"), role: .destructive) {
                                commentPendingDelete = comment
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
        }
        .padding(.vertical, TodoshiSpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private func start() async {
        stop()
        guard TaskCommentService.shared.isConfigured else { return }
        if let uid = currentUID {
            viewerRole = try? await SharedProjectMembersService.shared.currentUserRole(
                projectID: projectID,
                userID: uid
            )
            if let rows = try? await SharedProjectMembersService.shared.fetchMembers(projectID: projectID) {
                members = rows.assignmentCandidates
            }
        }
        listenerToken = TaskCommentService.shared.startListening(
            projectID: projectID,
            taskID: taskID,
            onChange: { rows in
                Task { @MainActor in
                    comments = rows
                }
            },
            onError: { _ in
                Task { @MainActor in
                    onError(TaskCommentStrings.postFailed)
                }
            }
        )
    }

    private func stop() {
        TaskCommentService.shared.stopListening(listenerToken)
        listenerToken = nil
    }

    @MainActor
    private func post() async {
        guard canCompose, let uid = currentUID else { return }
        switch TaskCommentBodyPolicy.validate(draft) {
        case .empty:
            onError(TaskCommentStrings.emptyBodyError)
            return
        case .tooLong:
            onError(TaskCommentStrings.tooLongError)
            return
        case .valid:
            break
        }
        isPosting = true
        defer { isPosting = false }
        let membershipName = members.first(where: { $0.uid == uid })?.displayName
        let sessionName = authSession.currentSession?.user.displayName
        let display = CollaborationDisplayNamePolicy.collaborationSnapshot(
            preferred: CollaborationDisplayNamePolicy.normalized(membershipName)
                ?? CollaborationDisplayNamePolicy.normalized(sessionName),
            uid: uid
        )
        do {
            try await TaskCommentService.shared.createComment(
                projectID: projectID,
                taskID: taskID,
                authorUID: uid,
                authorDisplayName: display,
                body: draft
            )
            draft = ""
            isComposerFocused = false
        } catch {
            onError(TaskCommentStrings.postFailed)
        }
    }

    @MainActor
    private func saveEdit() async {
        guard let comment = editingComment else { return }
        switch TaskCommentBodyPolicy.validate(editingBody) {
        case .empty:
            onError(TaskCommentStrings.emptyBodyError)
            return
        case .tooLong:
            onError(TaskCommentStrings.tooLongError)
            return
        case .valid:
            break
        }
        do {
            try await TaskCommentService.shared.updateBody(
                projectID: projectID,
                taskID: taskID,
                comment: comment,
                body: editingBody
            )
            editingComment = nil
        } catch {
            onError(TaskCommentStrings.postFailed)
        }
    }

    @MainActor
    private func confirmDelete() async {
        guard let comment = commentPendingDelete else { return }
        commentPendingDelete = nil
        do {
            try await TaskCommentService.shared.softDelete(
                projectID: projectID,
                taskID: taskID,
                comment: comment
            )
        } catch {
            onError(TaskCommentStrings.postFailed)
        }
    }
}
