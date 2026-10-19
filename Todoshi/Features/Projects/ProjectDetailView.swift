import SwiftUI
import SwiftData
import TodoshiCore

struct ProjectDetailView: View {
    let projectID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthSessionController.self) private var authSession
    @Query private var projects: [Project]

    @State private var isEditing = false
    @State private var isCreatingTask = false
    @State private var defaultNewStatus: TaskStatus = .todo
    @State private var newTaskColumnID: UUID?
    @State private var isEditingColumns = false
    @State private var editingTaskID: UUID?
    @State private var taskPendingDelete: TaskItem?
    @State private var showArchiveConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showShareConfirm = false
    @State private var isSharing = false
    @State private var navigateToMembers = false
    @State private var actionError: String?
    @State private var viewerRole: ProjectMemberRole?
    @State private var members: [ProjectMemberRow] = []
    @State private var membersListenerToken: UUID?
    @State private var assignmentFilter: TaskAssignmentFilter = .all
    @State private var toastMessage: String?

    init(projectID: UUID) {
        self.projectID = projectID
        let id = projectID
        _projects = Query(filter: #Predicate<Project> { $0.id == id })
    }

    private var project: Project? { projects.first }

    var body: some View {
        Group {
            if let project {
                content(for: project)
            } else {
                ContentUnavailableView(TodoshiL10n.tr("project.notFound"), systemImage: "folder.badge.questionmark")
            }
        }
    }

    /// My Tasks / My Items always resolves against the currently authenticated account.
    private var viewerUID: String? { authSession.currentSession?.user.id }

    private var viewerMembership: ProjectMemberRow? {
        guard let uid = viewerUID else { return nil }
        return members.first { $0.userId == uid }
    }

    private var canCreateChecklistItems: Bool {
        // Personal projects: always. Shared: owner or full member (Phase 6 root-create rules).
        guard project?.isShared == true else { return true }
        guard let membership = viewerMembership else { return false }
        return SharedTaskEditAuthorization.canCreateRootTask(
            role: membership.role,
            accessLevel: membership.resolvedAccessLevel
        )
    }

    @ViewBuilder
    private func content(for project: Project) -> some View {
        VStack(spacing: 0) {
            headerBar(project)
            if project.isShared {
                assignmentFilterPicker(for: project.projectType)
            }
            if project.isShared, project.isSyncUnavailable {
                Text(TodoshiL10n.tr("project.share.syncUnavailable"))
                    .font(TodoshiTypography.metadata)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, TodoshiSpacing.md)
                    .padding(.bottom, TodoshiSpacing.xs)
            } else if project.isShared, SharedProjectSyncService.shared.isContentSeeding(projectID: project.id) {
                Text(TodoshiL10n.tr("project.share.syncingContent"))
                    .font(TodoshiTypography.metadata)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, TodoshiSpacing.md)
                    .padding(.bottom, TodoshiSpacing.xs)
            }

            if project.isChecklist {
                checklistContent(for: project)
            } else {
                boardContent(for: project)
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(TodoshiBrand.groupedBackground)
        .todoshiToast(message: $toastMessage)
        .navigationDestination(isPresented: $navigateToMembers) {
            ProjectMembersView(projectID: project.id, projectName: project.name)
        }
        .toolbar {
            // The header already shows the project name prominently.
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !project.isShared || SharedProjectRolePermissions.canEditProjectMetadata(role: viewerRole) {
                        Button(TodoshiL10n.tr("project.edit")) { isEditing = true }
                    }
                    if ProjectColumnsPolicy.canEditColumns(project, isOwner: viewerRole == .owner) {
                        Button(TodoshiL10n.tr("columns.edit")) { isEditingColumns = true }
                    }
                    Button(ProjectTerminologyPolicy.addItem(project.projectType)) {
                        newTaskColumnID = nil
                        if project.isChecklist, !canCreateChecklistItems {
                            toastMessage = ProjectTerminologyPolicy.noEditPermission(for: .checklist)
                        } else {
                            defaultNewStatus = .todo
                            isCreatingTask = true
                        }
                    }
                    if project.isShared {
                        Button(TodoshiL10n.tr("project.members")) {
                            navigateToMembers = true
                        }
                    } else {
                        Button(TodoshiL10n.tr("project.share")) {
                            beginShareFlow(for: project)
                        }
                    }
                    if project.status == .active {
                        Button(TodoshiL10n.tr("project.archive"), role: .destructive) {
                            showArchiveConfirm = true
                        }
                    } else {
                        Button(TodoshiL10n.tr("project.restore")) { restore(project) }
                    }
                    Button(TodoshiL10n.tr("project.delete"), role: .destructive) {
                        showDeleteConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(TodoshiL10n.tr("project.actionsA11y"))
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                ProjectFormView(context: modelContext, projectID: project.id)
            }
        }
        .sheet(isPresented: $isCreatingTask) {
            NavigationStack {
                TaskFormView(
                    context: modelContext,
                    projectID: project.id,
                    taskID: nil,
                    initialStatus: defaultNewStatus,
                    initialColumnID: newTaskColumnID
                )
            }
        }
        .sheet(isPresented: $isEditingColumns) {
            NavigationStack {
                ProjectColumnsEditorView(project: project)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingTaskID != nil },
            set: { if !$0 { editingTaskID = nil } }
        )) {
            NavigationStack {
                if let editingTaskID {
                    TaskFormView(
                        context: modelContext,
                        projectID: project.id,
                        taskID: editingTaskID
                    )
                }
            }
        }
        .confirmationDialog(
            TodoshiL10n.format("project.archiveNamed", project.name),
            isPresented: $showArchiveConfirm,
            titleVisibility: .visible
        ) {
            Button(TodoshiL10n.tr("project.archiveShort")) { archive(project) }
            Button(TodoshiL10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(TodoshiL10n.tr("project.archiveMessage"))
        }
        .confirmationDialog(
            TodoshiL10n.tr("project.share.confirmTitle"),
            isPresented: $showShareConfirm,
            titleVisibility: .visible
        ) {
            Button(TodoshiL10n.tr("project.share.continue")) {
                Task { await performShare(project) }
            }
            Button(TodoshiL10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(TodoshiL10n.tr("project.share.confirmMessage"))
        }
        .alert(TodoshiL10n.tr("project.deleteConfirm"), isPresented: $showDeleteConfirm) {
            Button(TodoshiL10n.tr("common.delete"), role: .destructive) { delete(project) }
            Button(TodoshiL10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            let count = (project.tasks ?? []).count
            if count == 1 {
                Text(TodoshiL10n.format("project.deleteMessageOne", project.name))
            } else {
                Text(TodoshiL10n.format("project.deleteMessage", project.name, count))
            }
        }
        .alert(
            TodoshiL10n.tr("task.deleteConfirm"),
            isPresented: Binding(
                get: { taskPendingDelete != nil },
                set: { if !$0 { taskPendingDelete = nil } }
            ),
            presenting: taskPendingDelete
        ) { task in
            Button(TodoshiL10n.tr("common.delete"), role: .destructive) { deleteTask(task) }
            Button(TodoshiL10n.tr("common.cancel"), role: .cancel) {}
        } message: { task in
            let descendants = TaskRepository(context: modelContext).descendantCount(of: task)
            if descendants > 0 {
                if descendants == 1 {
                    Text(TodoshiL10n.tr("task.deleteAlsoSubtasksOne"))
                } else {
                    Text(TodoshiL10n.format("task.deleteAlsoSubtasks", descendants))
                }
            } else {
                Text(TodoshiL10n.format("task.deleteNamed", task.title))
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
        .overlay {
            if isSharing {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView(TodoshiL10n.tr("project.share.progress"))
                        .padding(TodoshiSpacing.lg)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: TodoshiRadius.md))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .onChange(of: authSession.currentSession?.user.id) { _, newValue in
            // Never keep a previous account's My Tasks selection.
            assignmentFilter = .all
            guard newValue != nil else {
                members = []
                return
            }
            resumePendingShareIfNeeded(for: project)
            Task { await refreshViewerRole(for: project) }
            startMembersListenerIfNeeded(for: project)
        }
        .onAppear {
            resumePendingShareIfNeeded(for: project)
            Task { await refreshViewerRole(for: project) }
            startMembersListenerIfNeeded(for: project)
        }
        .onDisappear {
            SharedProjectMembersService.shared.stopListening(membersListenerToken)
            membersListenerToken = nil
        }
    }

    private func assignmentFilterPicker(for type: ProjectType) -> some View {
        Picker(TaskAssignmentPresentation.assigneeSectionTitle, selection: $assignmentFilter) {
            ForEach(TaskAssignmentFilter.allCases) { filter in
                Text(filter.title(for: type)).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, TodoshiSpacing.md)
        .padding(.bottom, TodoshiSpacing.xs)
    }

    @ViewBuilder
    private func boardContent(for project: Project) -> some View {
        let board = ProjectBoardMapping.snapshot(
            from: project,
            assigneeNames: project.isShared ? members.assigneeDisplayNames : [:],
            filter: project.isShared ? assignmentFilter : .all,
            viewerUID: viewerUID
        )
        ProjectVerticalBoardView(
            snapshot: board,
            columns: ProjectColumnsPolicy.columns(for: project),
            canEditColumns: ProjectColumnsPolicy.canEditColumns(project, isOwner: viewerRole == .owner),
            onAddTask: { column in
                defaultNewStatus = column.kind.status
                newTaskColumnID = column.id
                isCreatingTask = true
            },
            onEditTask: { editingTaskID = $0 },
            onDeleteTask: { taskID in
                taskPendingDelete = try? TaskRepository(context: modelContext).fetchTask(id: taskID)
            },
            onMoveToColumn: { taskID, column in
                commitMove(taskID: taskID, to: column)
            },
            onEditColumns: { isEditingColumns = true }
        )
    }

    @ViewBuilder
    private func checklistContent(for project: Project) -> some View {
        let snapshot = ChecklistProjectMapping.snapshot(
            from: project,
            filter: project.isShared ? assignmentFilter : .all,
            viewerUID: viewerUID
        )
        ChecklistProjectListView(
            project: project,
            snapshot: snapshot,
            assigneeNames: project.isShared ? members.assigneeDisplayNames : [:],
            memberCandidates: project.isShared ? members.assignmentCandidates : [],
            viewerUID: viewerUID,
            isShared: project.isShared,
            canCreateItems: canCreateChecklistItems,
            canEditItem: { item in canEditChecklistItem(item) },
            completionActor: completionActor,
            onPermissionDenied: {
                toastMessage = ProjectTerminologyPolicy.noEditPermission(for: .checklist)
            },
            onError: { actionError = $0 }
        )
    }

    /// Actor who performs Shared Checklist completions — current authenticated membership.
    private var completionActor: TaskCompletionActor? {
        guard project?.isShared == true, let uid = viewerUID else { return nil }
        return TaskCompletionActor(uid: uid, displayName: viewerMembership?.displayName)
    }

    private func canEditChecklistItem(_ item: TaskItem) -> Bool {
        guard item.isLive else { return false }
        guard project?.isShared == true else { return true }
        guard let membership = viewerMembership else { return false }
        return SharedTaskEditAuthorization.canEditTaskContent(
            role: membership.role,
            accessLevel: membership.resolvedAccessLevel,
            viewerUID: viewerUID,
            rootEditorUIDs: SharedTaskEditorInheritance.editorUIDs(for: item)
        )
    }

    private func startMembersListenerIfNeeded(for project: Project) {
        guard project.isShared,
              membersListenerToken == nil,
              SharedProjectMembersService.shared.isConfigured,
              authSession.currentSession?.user.id != nil
        else { return }
        membersListenerToken = SharedProjectMembersService.shared.startListening(
            projectID: project.id,
            onChange: { rows in
                Task { @MainActor in members = rows }
            },
            onError: { _ in }
        )
    }

    private func refreshViewerRole(for project: Project) async {
        guard project.isShared,
              let uid = authSession.currentSession?.user.id else {
            viewerRole = nil
            return
        }
        viewerRole = try? await SharedProjectMembersService.shared.currentUserRole(
            projectID: project.id,
            userID: uid
        )
    }

    @ViewBuilder
    private func headerBar(_ project: Project) -> some View {
        let roots = (project.tasks ?? []).filter(\.isRoot)
        let doneCount = roots.filter { $0.status == .done }.count
        let percent = roots.isEmpty ? 0 : Int((Double(doneCount) / Double(roots.count) * 100).rounded())
        return HStack(alignment: .center, spacing: TodoshiSpacing.sm) {
            TodoshiProjectIconWell(
                systemName: project.icon,
                colorHex: project.colorHex,
                size: 48,
                projectType: project.projectType
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: TodoshiSpacing.xs) {
                    Text(project.name)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                    if project.isShared {
                        Image(systemName: SharedProjectPresentation.indicatorSystemImage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(SharedProjectPresentation.accessibilityLabel())
                    }
                }
                Text(
                    project.isChecklist
                        ? TodoshiL10n.format("projects.listProgress", doneCount, roots.count)
                        : TodoshiL10n.format("board.summary", roots.count, percent)
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if project.status == .archived {
                    Text(TodoshiL10n.tr("project.archivedBadge"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TodoshiSpacing.md)
        .padding(.top, TodoshiSpacing.xs)
        .padding(.bottom, TodoshiSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func beginShareFlow(for project: Project) {
        guard !project.isShared else {
            actionError = UserFacingError.message(for: CollaborationError.alreadyShared)
            return
        }
        guard SharedProjectBootstrapPolicy.isShareConversionEnabled else {
            actionError = UserFacingError.message(for: CollaborationError.shareConversionDisabled)
            return
        }

        switch authSession.requireAuthenticationForCollaboration() {
        case .requiresAuthentication:
            authSession.rememberPendingShareProject(id: project.id)
            return
        case .authenticated:
            showShareConfirm = true
        }
    }

    private func resumePendingShareIfNeeded(for project: Project) {
        guard authSession.pendingShareProjectID == project.id else { return }
        guard case .authenticated = authSession.authRequirement else { return }
        _ = authSession.consumePendingShareProjectID()
        guard !project.isShared else { return }
        guard SharedProjectBootstrapPolicy.isShareConversionEnabled else {
            actionError = UserFacingError.message(for: CollaborationError.shareConversionDisabled)
            return
        }
        Task {
            guard await authSession.ensureCollaborationIdentityReady() else {
                actionError = authSession.identityProvisioningWarning
                    ?? UserFacingError.message(for: CollaborationError.identityProvisioningFailed)
                return
            }
            showShareConfirm = true
        }
    }

    private func performShare(_ project: Project) async {
        guard !isSharing else { return }
        guard await authSession.ensureCollaborationIdentityReady() else {
            actionError = authSession.identityProvisioningWarning
                ?? UserFacingError.message(for: CollaborationError.identityProvisioningFailed)
            return
        }
        guard !project.isShared else {
            actionError = UserFacingError.message(for: CollaborationError.alreadyShared)
            return
        }
        guard SharedProjectBootstrapPolicy.isShareConversionEnabled else {
            actionError = UserFacingError.message(for: CollaborationError.shareConversionDisabled)
            return
        }

        isSharing = true
        defer { isSharing = false }

        let payload = SharedProjectBootstrapPayload(
            projectID: project.id,
            title: project.name,
            description: project.projectDescription,
            color: project.colorHex,
            displayName: authSession.currentSession?.user.displayName,
            projectType: project.projectType
        )

        do {
            _ = try await SharedProjectBootstrapService.shared.createSharedProject(payload)
            do {
                try ProjectRepository(context: modelContext).markSharedAfterRemoteBootstrap(
                    project,
                    collaborationOwnerUID: authSession.currentSession?.user.id
                )
            } catch {
                actionError = UserFacingError.message(for: CollaborationError.shareLocalSaveFailed)
            }
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    @discardableResult
    private func commitMove(taskID: UUID, to status: TaskStatus) -> Bool {
        let repo = TaskRepository(context: modelContext)
        do {
            let previousStatus = try repo.fetchTask(id: taskID)?.status
            let didWrite = try repo.move(
                taskID: taskID,
                to: status,
                before: nil,
                completionActor: completionActor
            )
            if didWrite {
                TodoshiHaptics.taskStatusChanged(crossStatus: previousStatus != status)
            }
            return didWrite
        } catch {
            actionError = UserFacingError.message(for: error)
            return false
        }
    }

    private func commitMove(taskID: UUID, to column: ProjectColumn) {
        do {
            try TaskRepository(context: modelContext).move(
                taskID: taskID,
                toColumn: column,
                completionActor: completionActor
            )
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    private func deleteTask(_ task: TaskItem) {
        do {
            try TaskRepository(context: modelContext).delete(task, mode: .deleteDescendants)
            taskPendingDelete = nil
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    private func archive(_ project: Project) {
        do {
            try ProjectRepository(context: modelContext).archive(project)
            dismiss()
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    private func restore(_ project: Project) {
        do {
            try ProjectRepository(context: modelContext).restore(project)
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    private func delete(_ project: Project) {
        do {
            try ProjectRepository(context: modelContext).delete(project)
            dismiss()
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }
}
