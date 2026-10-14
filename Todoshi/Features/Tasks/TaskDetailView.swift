import SwiftUI
import SwiftData
import TodoshiCore

struct TaskDetailView: View {
    let taskID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthSessionController.self) private var authSession
    @Query private var tasks: [TaskItem]

    @State private var isEditing = false
    @State private var subtaskForm: TaskSubtaskFormContext?
    @State private var showDeleteConfirm = false
    @State private var showDeleteChoice = false
    @State private var showPromoteConfirm = false
    @State private var actionError: String?
    @State private var toastMessage: String?
    @State private var membership: ProjectMemberRow?
    @State private var projectMembers: [ProjectMemberRow] = []
    @State private var membersListenerToken: UUID?
    @State private var selectedTab: TaskDetailContentTab = .details

    init(taskID: UUID) {
        self.taskID = taskID
        let id = taskID
        _tasks = Query(filter: #Predicate<TaskItem> { $0.id == id })
    }

    private var task: TaskItem? { tasks.first }

    private var viewerUID: String? { authSession.currentSession?.user.id }

    private var canEditTaskContent: Bool {
        guard let task else { return false }
        guard let project = task.project, project.isShared else { return true }
        guard let membership else { return true }
        return SharedTaskEditAuthorization.canEditTaskContent(
            role: membership.role,
            accessLevel: membership.resolvedAccessLevel,
            viewerUID: viewerUID,
            rootEditorUIDs: SharedTaskEditorInheritance.editorUIDs(for: task)
        )
    }

    private var canManageTaskACL: Bool {
        SharedTaskEditAuthorization.canManageTaskEditorUIDs(role: membership?.role)
    }

    private var canAssignTask: Bool {
        TaskAssignmentPolicy.canAssign(role: membership?.role)
    }

    private var projectType: ProjectType {
        task?.project?.projectType ?? .tasks
    }

    private var isChecklistProject: Bool {
        projectType == .checklist
    }

    var body: some View {
        Group {
            if let task {
                content(for: task)
            } else {
                ContentUnavailableView(TodoshiL10n.tr("task.notFoundTitle"), systemImage: "checkmark.circle.badge.questionmark")
            }
        }
        .todoshiToast(message: $toastMessage)
        .onAppear {
            startMembershipListenerIfNeeded()
            if let task { markCollaborationActivitySeenIfNeeded(for: task) }
        }
        .onChange(of: task?.lastActivityAt) { _, _ in
            if let task { markCollaborationActivitySeenIfNeeded(for: task) }
        }
        .onDisappear {
            SharedProjectMembersService.shared.stopListening(membersListenerToken)
            membersListenerToken = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: SharedTaskPermissionDeniedCenter.notification)) { note in
            guard let taskIDString = note.userInfo?[SharedTaskPermissionDeniedCenter.taskIDKey] as? String,
                  taskIDString == taskID.uuidString
            else { return }
            presentPermissionFeedback(.revoked)
        }
    }

    @ViewBuilder
    private func content(for task: TaskItem) -> some View {
        let isRoot = task.isRoot
        let childCount = TaskRepository(context: modelContext).descendantCount(of: task)
        let editable = canEditTaskContent
        let rootForACL = task.parentTask ?? task
        let isShared = task.project?.isShared == true
        let showsCommentsTab = isShared
        let candidates = projectMembers.assignmentCandidates
        let assigneeName = TaskAssignmentPresentation.assigneeName(
            for: rootForACL.assigneeUID,
            members: candidates
        )

        List {
            if isShared, !editable {
                Section {
                    TaskDetailReadOnlyBanner(
                        message: isChecklistProject
                            ? ProjectTerminologyPolicy.noEditPermission(for: .checklist)
                            : SharedTaskPermissionPresentation.noEditPermission
                    )
                }
                .listRowInsets(cardInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                TaskDetailHeroView(
                    projectName: task.project?.name,
                    projectIcon: task.project?.icon,
                    projectColorHex: task.project?.colorHex,
                    projectType: projectType,
                    title: task.title,
                    status: task.status,
                    priority: task.priority,
                    dueDate: task.dueDate,
                    assigneeName: isShared && isRoot && rootForACL.assigneeUID != nil ? assigneeName : nil,
                    isEditable: editable,
                    onStatusSelect: { status in
                        if isRoot {
                            move(task, to: status)
                        } else if !isChecklistProject {
                            setChildStatus(task, status)
                        }
                    },
                    onEdit: { _ = performIfEditable({ isEditing = true }) }
                )
            }
            .listRowInsets(cardInsets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if showsCommentsTab {
                Section {
                    TaskDetailSectionPicker(selection: $selectedTab)
                }
                .listRowInsets(cardInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if !showsCommentsTab || selectedTab == .details {
                detailsSections(
                    task: task,
                    isRoot: isRoot,
                    editable: editable,
                    rootForACL: rootForACL,
                    isShared: isShared,
                    childCount: childCount
                )
            }

            if showsCommentsTab, selectedTab == .comments, let project = task.project {
                Section {
                    TaskDetailCommentsSection(
                        projectID: project.id,
                        taskID: task.id,
                        isTaskSoftDeleted: task.deletedAt != nil,
                        embedInList: true,
                        showsSectionHeader: false,
                        onError: { actionError = $0 }
                    )
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(TodoshiSpacing.sm)
        .scrollContentBackground(.hidden)
        .background(TodoshiBrand.groupedBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(TodoshiL10n.tr("common.edit")) {
                        guard performIfEditable({ isEditing = true }) else { return }
                    }
                    if isRoot {
                        Menu(TodoshiL10n.tr("task.moveToStatus")) {
                            ForEach(ProjectTypeCapabilities.allowedStatuses(for: projectType), id: \.self) { status in
                                Button(ProjectStatusPolicy.displayName(status, for: projectType)) {
                                    move(task, to: status)
                                }
                                .disabled(editable && task.status == status)
                            }
                        }
                    } else if !isChecklistProject {
                        Menu(TodoshiL10n.tr("task.moveToStatus")) {
                            ForEach(ProjectTypeCapabilities.allowedStatuses(for: projectType), id: \.self) { status in
                                Button(ProjectStatusPolicy.displayName(status, for: projectType)) {
                                    setChildStatus(task, status)
                                }
                                .disabled(editable && task.status == status)
                            }
                        }
                        Button(SubtaskStrings.promoteToRoot) {
                            guard performIfEditable({ showPromoteConfirm = true }) else { return }
                        }
                    }
                    Button(TodoshiL10n.tr("common.delete"), role: .destructive) {
                        guard performIfEditable({
                            if isRoot, childCount > 0 {
                                showDeleteChoice = true
                            } else {
                                showDeleteConfirm = true
                            }
                        }) else { return }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(TodoshiL10n.tr("task.actionsA11y"))
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                if let projectID = task.project?.id {
                    TaskFormView(
                        context: modelContext,
                        projectID: projectID,
                        taskID: task.id
                    )
                }
            }
        }
        .sheet(item: $subtaskForm) { context in
            NavigationStack {
                TaskFormView(
                    context: modelContext,
                    projectID: context.projectID,
                    parentTaskID: context.parentTaskID
                )
            }
        }
        .confirmationDialog(
            SubtaskStrings.deleteTaskTitle,
            isPresented: $showDeleteChoice,
            titleVisibility: .visible
        ) {
            Button(SubtaskStrings.deleteAllSubtasks, role: .destructive) {
                delete(task, mode: .deleteDescendants)
            }
            Button(SubtaskStrings.promoteSubtasks) {
                delete(task, mode: .promoteChildren)
            }
            Button(TodoshiL10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(deletionChoiceMessage(title: task.title, count: childCount))
        }
        .alert(SubtaskStrings.deleteTaskTitle, isPresented: $showDeleteConfirm) {
            Button(TodoshiL10n.tr("common.delete"), role: .destructive) {
                delete(task, mode: .deleteDescendants)
            }
            Button(TodoshiL10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            if task.isRecurring || task.recurrenceSeriesID != nil {
                Text("“\(task.title)” will be permanently deleted. \(TaskRecurrenceStrings.thisOccurrenceOnly)")
            } else {
                Text("“\(task.title)” will be permanently deleted.")
            }
        }
        .alert(SubtaskStrings.promoteConfirmTitle, isPresented: $showPromoteConfirm) {
            Button(SubtaskStrings.promoteToRoot) { promote(task) }
            Button(TodoshiL10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(SubtaskStrings.promoteConfirmMessage)
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
    }

    @ViewBuilder
    private func detailsSections(
        task: TaskItem,
        isRoot: Bool,
        editable: Bool,
        rootForACL: TaskItem,
        isShared: Bool,
        childCount: Int
    ) -> some View {
        if !task.taskDescription.isEmpty {
            Section {
                Text(task.taskDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .listRowInsets(cardInsets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

        if ProjectTypeCapabilities.supportsNestedChecklist(projectType), !(task.checklist ?? []).isEmpty {
            TaskDetailChecklistSection(
                taskID: task.id,
                items: task.checklist ?? [],
                isEditable: editable,
                onPermissionDenied: {
                    presentPermissionFeedback(.deniedEdit(projectType))
                },
                onError: { actionError = $0 }
            )
        }

        if isRoot, ProjectTypeCapabilities.supportsSubtasks(projectType) {
            TaskDetailSubtasksSection(
                parent: task,
                isEditable: editable,
                onPermissionDenied: {
                    presentPermissionFeedback(.deniedEdit(projectType))
                },
                onError: { actionError = $0 },
                onAddSubtask: { parentTaskID, projectID in
                    guard performIfEditable({
                        subtaskForm = TaskSubtaskFormContext(
                            parentTaskID: parentTaskID,
                            projectID: projectID
                        )
                    }) else { return }
                }
            )
        }

        let assigned = (task.labels ?? []).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        if !assigned.isEmpty {
            Section(LabelStrings.labels) {
                ForEach(assigned, id: \.id) { label in
                    NavigationLink(value: AppRoute.labelTasks(label.id)) {
                        LabelChipView(name: label.name, colorHex: label.colorHex)
                    }
                    .accessibilityLabel(TodoshiL10n.format("label.chipA11y", label.name, LabelColorCatalog.name(for: label.colorHex)))
                }
            }
        }

        if ProjectTypeCapabilities.supportsResources(projectType), !(task.resources ?? []).isEmpty {
            TaskDetailResourcesSection(
                taskID: task.id,
                resources: task.resources ?? [],
                isEditable: editable,
                onPermissionDenied: {
                    presentPermissionFeedback(.deniedEdit(projectType))
                },
                onError: { actionError = $0 }
            )
        }

        if isShared, isRoot {
            TaskDetailAssignmentSection(
                projectID: task.project!.id,
                rootTask: rootForACL,
                members: projectMembers,
                canAssign: canAssignTask,
                onError: { actionError = $0 }
            )
        }

        if canManageTaskACL, isShared, isRoot {
            TaskDetailPermissionsSection(
                projectID: task.project!.id,
                rootTask: rootForACL,
                members: projectMembers,
                onError: { actionError = $0 },
                onGuard: { toastMessage = $0 }
            )
        }

        if !isChecklistProject,
           isRoot,
           task.isRecurring || task.previousOccurrenceID != nil || task.nextOccurrenceID != nil {
            recurrenceSection(for: task)
        }

        if let parent = task.parentTask, !isChecklistProject {
            TaskDetailParentContextSection(
                parent: parent,
                projectName: parent.project?.name ?? task.project?.name,
                canPromote: true,
                onPromote: {
                    guard performIfEditable({ showPromoteConfirm = true }) else { return }
                }
            )
        }

        if let reminder = task.reminderDate {
            Section(TodoshiL10n.tr("common.reminder")) {
                LabeledContent(TodoshiL10n.tr("reminder.remindAt")) {
                    Text(reminder, format: .dateTime.day().month().year().hour().minute())
                }
            }
        }

        if !task.notes.isEmpty {
            Section {
                TaskDetailTextCard(
                    title: TodoshiL10n.tr("common.notes"),
                    text: task.notes
                )
            }
            .listRowInsets(cardInsets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

        if editable {
            Section {
                TaskDetailMoreActions { _ = performIfEditable({ isEditing = true }) }
            }
            .listRowInsets(cardInsets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

        Section {
            Text(TodoshiL10n.format("task.createdLine", task.createdAt.formatted(.dateTime.day().month().year().locale(AppLanguageStore.resolvedLocale))))
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var cardInsets: EdgeInsets {
        EdgeInsets(
            top: 0,
            leading: TodoshiSpacing.md,
            bottom: 0,
            trailing: TodoshiSpacing.md
        )
    }

    private func metadataCardIsNonEmpty(
        task: TaskItem,
        project: Project?,
        assigneeName: String,
        showsAssignee: Bool,
        completionLine: String?
    ) -> Bool {
        project != nil
            || (showsAssignee)
            || (task.priority != .none && !isChecklistProject)
            || task.dueDate != nil
            || completionLine != nil
    }

    private func checklistCompletionLine(
        for task: TaskItem,
        members: [AssignmentCandidate]
    ) -> String? {
        guard isChecklistProject else { return nil }
        return TaskCompletionPresentation.completedByLine(
            completedByUID: task.completedByUID,
            completedByDisplayName: task.completedByDisplayName,
            members: members
        )
    }

    @discardableResult
    private func requireEditPermission() -> Bool {
        let feedback = SharedTaskPermissionFeedback.forEditAttempt(
            canEditTaskContent: canEditTaskContent,
            projectType: projectType
        )
        if feedback.shouldShowToast {
            presentPermissionFeedback(feedback)
            return false
        }
        return true
    }

    @discardableResult
    private func performIfEditable(_ action: () -> Void) -> Bool {
        guard requireEditPermission() else { return false }
        action()
        return true
    }

    private func presentPermissionFeedback(_ feedback: SharedTaskPermissionFeedback) {
        guard let message = feedback.toastMessage else { return }
        toastMessage = message
    }

    private func startMembershipListenerIfNeeded() {
        guard let project = task?.project, project.isShared else { return }
        SharedProjectMembersService.shared.stopListening(membersListenerToken)
        let uid = viewerUID
        membersListenerToken = SharedProjectMembersService.shared.startListening(
            projectID: project.id,
            onChange: { rows in
                Task { @MainActor in
                    projectMembers = rows
                    if let uid {
                        membership = rows.first(where: { $0.userId == uid })
                    }
                }
            },
            onError: { _ in }
        )
    }

    private func deletionChoiceMessage(title: String, count: Int) -> String {
        let del = SubtaskStrings.deleteWithDescendantsMessage(count: count)
        let promote = SubtaskStrings.deleteWithPromotionMessage(count: count)
        let header = TodoshiL10n.format("subtasks.hasCount", title, count)
        return "\(header)\n\n• \(del)\n• \(promote)"
    }

    @ViewBuilder
    private func recurrenceSection(for task: TaskItem) -> some View {
        Section {
            if let rule = task.recurrenceRule {
                LabeledContent(TaskRecurrenceStrings.recurringTask) {
                    Text(rule.summary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(TaskRecurrenceStrings.recurringTask), \(rule.summary)")
            } else if task.recurrenceSeriesID != nil {
                Text(TaskRecurrenceStrings.doesNotRepeat)
                    .foregroundStyle(.secondary)
            }

            if let previousID = task.previousOccurrenceID {
                NavigationLink(value: AppRoute.task(previousID)) {
                    Text(TaskRecurrenceStrings.previousOccurrence)
                }
                .accessibilityLabel(TaskRecurrenceStrings.previousOccurrence)
            }

            if let nextID = task.nextOccurrenceID {
                NavigationLink(value: AppRoute.task(nextID)) {
                    Text(TaskRecurrenceStrings.nextOccurrence)
                }
                .accessibilityLabel(TaskRecurrenceStrings.nextOccurrence)
            }
        } header: {
            Text(TaskRecurrenceStrings.repeatSection)
        } footer: {
            if task.isRecurring {
                Text(TaskRecurrenceStrings.stopRepeating + " via Edit. " + TaskRecurrenceStrings.thisOccurrenceOnly)
            }
        }
    }

    private func move(_ task: TaskItem, to status: TaskStatus) {
        guard requireEditPermission() else { return }
        do {
            try TaskRepository(context: modelContext).moveToStatus(
                task,
                status,
                completionActor: completionActor
            )
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    private var completionActor: TaskCompletionActor? {
        guard task?.project?.isShared == true, let uid = viewerUID else { return nil }
        return TaskCompletionActor(uid: uid, displayName: membership?.displayName)
    }

    private func setChildStatus(_ task: TaskItem, _ status: TaskStatus) {
        guard requireEditPermission() else { return }
        do {
            try TaskRepository(context: modelContext).update(
                task,
                title: task.title,
                taskDescription: task.taskDescription,
                status: status,
                priority: task.priority,
                dueDate: task.dueDate,
                reminderDate: task.reminderDate,
                notes: task.notes,
                labelIDs: nil,
                completionActor: completionActor
            )
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    private func promote(_ task: TaskItem) {
        guard requireEditPermission() else { return }
        do {
            try TaskRepository(context: modelContext).promoteToRoot(taskID: task.id)
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    private func delete(_ task: TaskItem, mode: TaskDeletionMode) {
        guard requireEditPermission() else { return }
        do {
            try TaskRepository(context: modelContext).delete(task, mode: mode)
            dismiss()
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    private func markCollaborationActivitySeenIfNeeded(for task: TaskItem) {
        guard task.project?.isShared == true else { return }
        let root = task.isRoot ? task : (task.parentTask ?? task)
        TaskActivitySeenStore.markSeen(
            uid: viewerUID,
            projectID: root.project?.id,
            rootTaskID: root.id,
            lastSeenAt: root.lastActivityAt
        )
    }
}

// MARK: - Hero header

/// Title, completion circle and tappable property pills at the top of task detail.
struct TaskDetailHeroView: View {
    let projectName: String?
    let projectIcon: String?
    let projectColorHex: String?
    let projectType: ProjectType
    let title: String
    let status: TaskStatus
    let priority: TaskPriority
    let dueDate: Date?
    let assigneeName: String?
    let isEditable: Bool
    let onStatusSelect: (TaskStatus) -> Void
    let onEdit: () -> Void

    private var isDone: Bool { status == .done }
    private var isOverdue: Bool { TaskPredicates.isOverdue(dueDate, status: status) }

    var body: some View {
        VStack(alignment: .leading, spacing: TodoshiSpacing.md) {
            if let projectName {
                let tint = TodoshiColor.from(hex: projectColorHex ?? ProjectColorCatalog.defaultHex)
                Label(projectName, systemImage: projectType == .checklist ? "checklist" : (projectIcon ?? "folder"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, TodoshiSpacing.sm)
                    .padding(.vertical, 6)
                    .background(tint.opacity(0.12), in: Capsule())
            }

            HStack(alignment: .top, spacing: TodoshiSpacing.xs) {
                TodoshiCompletionCircle(isDone: isDone, isOverdue: isOverdue, size: 28) {
                    guard isEditable else { return }
                    onStatusSelect(isDone ? .todo : .done)
                }
                .padding(.top, -6)
                Text(title)
                    .font(.title2.weight(.bold))
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TodoshiSpacing.xs) {
                    statusPill
                    pill(
                        isOverdue ? TodoshiL10n.tr("common.overdue") : dueText,
                        systemImage: "calendar",
                        tint: isOverdue ? .red : (dueDate == nil ? .secondary : TodoshiBrand.accent),
                        action: onEdit
                    )
                    if let assigneeName {
                        pill(assigneeName, systemImage: "person.fill", tint: TodoshiBrand.accent, action: onEdit)
                    }
                    if priority == .high || priority == .urgent {
                        pill(priority.displayName, systemImage: "flag.fill", tint: .orange, action: onEdit)
                    }
                }
            }
            .scrollClipDisabled()
        }
        .padding(.vertical, TodoshiSpacing.xs)
    }

    private var dueText: String {
        guard let dueDate else { return TodoshiL10n.tr("task.noDueDate") }
        return dueDate.formatted(
            .dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppLanguageStore.resolvedLocale)
        )
    }

    private var statusPill: some View {
        Menu {
            ForEach(ProjectTypeCapabilities.allowedStatuses(for: projectType), id: \.self) { option in
                Button(ProjectStatusPolicy.displayName(option, for: projectType)) {
                    onStatusSelect(option)
                }
            }
        } label: {
            pillLabel(
                ProjectStatusPolicy.displayName(status, for: projectType),
                systemImage: "circle.fill",
                tint: TodoshiStatusColor.indicator(for: status)
            )
        }
        .disabled(!isEditable)
    }

    private func pill(_ text: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            pillLabel(text, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
    }

    private func pillLabel(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(text)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, TodoshiSpacing.sm)
        .frame(minHeight: 34)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Secondary task properties collapsed into one row of shortcuts into the editor.
struct TaskDetailMoreActions: View {
    let onTap: () -> Void

    private let items: [(key: String, icon: String)] = [
        ("task.more.attachment", "paperclip"),
        ("task.more.reminder", "bell"),
        ("task.more.repeat", "repeat"),
        ("task.more.label", "tag"),
    ]

    var body: some View {
        HStack(spacing: TodoshiSpacing.xs) {
            ForEach(items, id: \.key) { item in
                Button(action: onTap) {
                    VStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.body.weight(.medium))
                            .foregroundStyle(TodoshiBrand.accent)
                        Text(TodoshiL10n.tr(item.key))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .todoshiSurface(cornerRadius: TodoshiRadius.lg)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, TodoshiSpacing.xs)
    }
}
