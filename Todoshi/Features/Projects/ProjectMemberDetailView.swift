import SwiftUI
import SwiftData
import TodoshiCore

/// Member profile + owner management for project membership.
struct ProjectMemberDetailView: View {
    let projectID: UUID
    let memberUserId: String
    let members: [ProjectMemberRow]
    let isOwnerViewer: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthSessionController.self) private var authSession
    @Query private var projects: [Project]

    @State private var accessLevel: ProjectMemberAccessLevel
    @State private var isSaving = false
    @State private var actionError: String?
    @State private var guardMessage: String?
    @State private var showRemoveConfirm = false
    @State private var showLeaveConfirm = false
    @State private var memberTodoshiID: String?
    @State private var isLoadingTodoshiID = false

    init(
        projectID: UUID,
        memberUserId: String,
        members: [ProjectMemberRow],
        isOwnerViewer: Bool
    ) {
        self.projectID = projectID
        self.memberUserId = memberUserId
        self.members = members
        self.isOwnerViewer = isOwnerViewer
        let initialMember = members.first { $0.userId == memberUserId }
        _accessLevel = State(initialValue: initialMember?.resolvedAccessLevel ?? .full)
        let id = projectID
        _projects = Query(filter: #Predicate<Project> { $0.id == id })
    }

    private var member: ProjectMemberRow? {
        members.first { $0.userId == memberUserId }
    }

    private var project: Project? { projects.first }

    private var currentUserUID: String? { authSession.currentSession?.user.id }

    private var canManage: Bool {
        guard let member else { return false }
        return MemberProfilePresentationPolicy.showsOwnerManagementControls(
            isOwnerViewer: isOwnerViewer,
            memberRole: member.role
        )
    }

    private var showRemoveAction: Bool { canManage }

    private var showLeaveAction: Bool {
        guard let uid = currentUserUID, let member else { return false }
        return member.userId == uid && member.role != .owner
    }

    private var displayName: String {
        MemberProfilePresentationPolicy.displayName(from: member?.displayName)
    }

    private var showsTodoshiID: Bool {
        guard let member else { return false }
        return MemberProfilePresentationPolicy.showsTodoshiID(
            isOwnerViewer: isOwnerViewer,
            memberRole: member.role
        )
    }

    private var showsWorkSummary: Bool {
        MemberProfilePresentationPolicy.showsWorkSummary(
            isOwnerViewer: isOwnerViewer,
            memberUID: memberUserId,
            viewerUID: currentUserUID
        )
    }

    private var showsAccessSummary: Bool {
        MemberProfilePresentationPolicy.showsAccessSummary(
            isOwnerViewer: isOwnerViewer,
            memberUID: memberUserId,
            viewerUID: currentUserUID
        )
    }

    private var rootTasks: [TaskItem] {
        let tasks = (project?.tasks ?? []).filter { $0.deletedAt == nil && $0.isRoot }
        return tasks.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private var assignedTasks: [TaskItem] {
        MemberAssignmentProgressPolicy.assignedRootTasks(for: memberUserId, in: rootTasks)
    }

    private var progress: MemberAssignmentProgress {
        MemberAssignmentProgressPolicy.progress(
            for: memberUserId,
            in: rootTasks,
            projectType: project?.projectType ?? .tasks
        )
    }

    private var projectType: ProjectType {
        project?.projectType ?? .tasks
    }

    private var currentCandidate: AssignmentCandidate {
        AssignmentCandidate(
            uid: memberUserId,
            role: member?.role ?? .member,
            accessLevel: accessLevel,
            displayName: member?.displayName
        )
    }

    var body: some View {
        Group {
            if member == nil {
                ContentUnavailableView(
                    TodoshiL10n.tr("project.members.empty"),
                    systemImage: "person.crop.circle.badge.xmark"
                )
            } else {
                memberProfileList
            }
        }
        .navigationTitle(MemberProfilePresentationPolicy.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .onChange(of: member?.resolvedAccessLevel) { _, newLevel in
            guard let newLevel, !isSaving else { return }
            accessLevel = newLevel
        }
        .task(id: memberUserId) {
            await loadTodoshiIDIfNeeded()
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
        .alert(
            TaskAssignmentPresentation.assigneeSectionTitle,
            isPresented: Binding(
                get: { guardMessage != nil },
                set: { if !$0 { guardMessage = nil } }
            )
        ) {
            Button(TodoshiL10n.tr("common.ok"), role: .cancel) {}
        } message: {
            Text(guardMessage ?? "")
        }
        .confirmationDialog(
            String(format: TodoshiL10n.tr("project.members.removeConfirmTitle"), displayName),
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button(TodoshiL10n.tr("project.members.remove"), role: .destructive) {
                Task { await removeMember() }
            }
            Button(TodoshiL10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(TodoshiL10n.tr("project.members.removeConfirmMessage"))
        }
        .confirmationDialog(
            TodoshiL10n.tr("project.members.leaveConfirmTitle"),
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button(TodoshiL10n.tr("project.members.leave"), role: .destructive) {
                Task { await leaveProject() }
            }
            Button(TodoshiL10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(TodoshiL10n.tr("project.members.leaveConfirmMessage"))
        }
    }

    private var memberProfileList: some View {
        List {
            profileHeaderSection

            if showsAccessSummary, let member {
                accessSummarySection(for: member)
            }

            if showsWorkSummary {
                assignmentProgressSection
                assignedTasksSection
            }

            if canManage, let member {
                permissionManagementSection(for: member)
            }

            if showRemoveAction || showLeaveAction {
                lifecycleSection
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var profileHeaderSection: some View {
        Section {
            VStack(spacing: TodoshiSpacing.xs) {
                TodoshiAvatar(
                    displayName: member?.displayName,
                    size: 72
                )

                Text(displayName)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                if let member {
                    Text(SharedProjectPresentation.memberRoleLabel(member.role))
                        .font(TodoshiTypography.metadata)
                        .foregroundStyle(.secondary)
                }

                if showsTodoshiID {
                    todoshiIDRow
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TodoshiSpacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                MemberProfilePresentationPolicy.accessibilityLabel(
                    displayName: displayName,
                    role: member?.role ?? .member,
                    todoshiId: memberTodoshiID
                )
            )
        }
    }

    @ViewBuilder
    private var todoshiIDRow: some View {
        VStack(spacing: 4) {
            Text(TodoshiL10n.tr("identity.todoshiId.label"))
                .font(TodoshiTypography.metadata)
                .foregroundStyle(.secondary)

            if isLoadingTodoshiID {
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 2)
            } else if let memberTodoshiID {
                Text(memberTodoshiID)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func accessSummarySection(for member: ProjectMemberRow) -> some View {
        Section(MemberProfilePresentationPolicy.permissionsSummaryTitle) {
            Text(
                MemberProfilePresentationPolicy.accessSummary(
                    role: member.role,
                    accessLevel: member.resolvedAccessLevel
                )
            )
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var assignmentProgressSection: some View {
        let snapshot = progress
        let type = projectType
        Section(ProjectTerminologyPolicy.assignedSection(type)) {
            Text("\(snapshot.total)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(ProjectStatusPolicy.progressStatuses(for: type), id: \.self) { status in
                let count = snapshot.count(for: status)
                if count > 0 {
                    LabeledContent(ProjectStatusPolicy.displayName(status, for: type)) {
                        Text("\(count)")
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var assignedTasksSection: some View {
        if !assignedTasks.isEmpty {
            Section(ProjectTerminologyPolicy.assignedSection(projectType)) {
                ForEach(assignedTasks, id: \.id) { task in
                    NavigationLink(value: AppRoute.task(task.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                            Text(ProjectStatusPolicy.displayName(task.status, for: projectType))
                                .font(TodoshiTypography.metadata)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func permissionManagementSection(for member: ProjectMemberRow) -> some View {
        if member.role == .owner {
            Section(SharedTaskPermissionPresentation.sectionTitle) {
                Text(SharedTaskPermissionPresentation.alwaysOwner)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                accessLevelPicker
            } header: {
                Text(SharedTaskPermissionPresentation.sectionTitle)
            } footer: {
                Text(
                    accessLevel == .full
                        ? SharedTaskPermissionPresentation.fullAccessHint
                        : SharedTaskPermissionPresentation.selectedHint
                )
            }

            if accessLevel == .restricted {
                Section(SharedTaskPermissionPresentation.allowedTasks) {
                    if rootTasks.isEmpty {
                        Text(TodoshiL10n.tr("project.members.empty"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rootTasks, id: \.id) { task in
                            Toggle(isOn: Binding(
                                get: { (task.editorUIDs ?? []).contains(memberUserId) },
                                set: { enabled in
                                    setEditor(enabled, for: task)
                                }
                            )) {
                                Text(task.title)
                            }
                            .disabled(!canManage || isSaving)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var lifecycleSection: some View {
        Section {
            if showRemoveAction {
                Button(TodoshiL10n.tr("project.members.remove"), role: .destructive) {
                    showRemoveConfirm = true
                }
                .disabled(isSaving)
            }
            if showLeaveAction {
                Button(TodoshiL10n.tr("project.members.leave"), role: .destructive) {
                    showLeaveConfirm = true
                }
                .disabled(isSaving)
            }
        }
    }

    @ViewBuilder
    private var accessLevelPicker: some View {
        Picker(SharedTaskPermissionPresentation.sectionTitle, selection: Binding(
            get: { accessLevel },
            set: { newValue in
                guard canManage, newValue != accessLevel else { return }
                Task { await applyAccessLevel(newValue) }
            }
        )) {
            Text(SharedTaskPermissionPresentation.fullAccess)
                .tag(ProjectMemberAccessLevel.full)
            Text(SharedTaskPermissionPresentation.selectedTasksOnly)
                .tag(ProjectMemberAccessLevel.restricted)
        }
        .pickerStyle(.inline)
        .labelsHidden()
        .disabled(!canManage)
    }

    private func loadTodoshiIDIfNeeded() async {
        guard showsTodoshiID else {
            memberTodoshiID = nil
            isLoadingTodoshiID = false
            return
        }
        isLoadingTodoshiID = true
        defer { isLoadingTodoshiID = false }
        do {
            let identity = try await TodoshiPublicIdentityService.shared.fetchPublicIdentity(for: memberUserId)
            memberTodoshiID = identity?.todoshiId
        } catch {
            memberTodoshiID = nil
        }
    }

    private func removeMember() async {
        guard let ownerUID = currentUserUID, let member else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await SharedProjectMemberLifecycleService.shared.removeMember(
                projectID: projectID,
                targetUID: member.userId,
                actingUID: ownerUID,
                targetRole: member.role
            )
            dismiss()
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    private func leaveProject() async {
        guard let uid = currentUserUID, let member else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await SharedProjectMemberLifecycleService.shared.leaveProject(
                projectID: projectID,
                actingUID: uid,
                memberRole: member.role
            )
            await SharedProjectSyncService.shared.evictSharedProjectAfterDeparture(
                projectID: projectID,
                voluntary: true
            )
            dismiss()
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    private func applyAccessLevel(_ level: ProjectMemberAccessLevel) async {
        guard canManage else { return }
        isSaving = true
        defer { isSaving = false }
        if level == .restricted {
            repairAssignedTaskACL()
        }
        do {
            try await SharedProjectMembersService.shared.updateAccessLevel(
                projectID: projectID,
                memberUID: memberUserId,
                accessLevel: level
            )
            accessLevel = level
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    private func repairAssignedTaskACL() {
        let pending = TaskAssignmentIntegrityPolicy.rootTasksNeedingRepair(
            forDemotedUID: memberUserId,
            rootTasks: rootTasks
        )
        guard !pending.isEmpty else { return }
        for task in pending {
            task.editorUIDs = TaskAssignmentIntegrityPolicy.repairedEditorUIDs(
                for: task,
                uid: memberUserId
            )
            task.updatedAt = .now
        }
        do {
            try modelContext.save()
            for task in pending {
                SharedProjectMutationHook.emit(.taskUpsert(projectID: projectID, taskID: task.id))
            }
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    private func setEditor(_ enabled: Bool, for task: TaskItem) {
        guard canManage, task.isRoot else { return }
        if !enabled,
           !TaskAssignmentIntegrityPolicy.canRemoveEditor(
               uid: memberUserId,
               assigneeUID: task.assigneeUID,
               candidate: currentCandidate
           ) {
            guardMessage = TaskAssignmentPresentation.assigneeAclGuard
            return
        }
        let next = SharedTaskEditorInheritance.withEditor(
            task.editorUIDs ?? [],
            including: memberUserId,
            enabled: enabled
        )
        task.editorUIDs = next
        task.updatedAt = .now
        do {
            try modelContext.save()
            SharedProjectMutationHook.emit(.taskUpsert(projectID: projectID, taskID: task.id))
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }
}
