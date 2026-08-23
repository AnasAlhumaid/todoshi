import SwiftUI
import SwiftData
import NexusCore

struct ProjectDetailView: View {
    let projectID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var projects: [Project]

    @State private var isEditing = false
    @State private var isCreatingTask = false
    @State private var defaultNewStatus: TaskStatus = .todo
    @State private var editingTaskID: UUID?
    @State private var taskPendingDelete: TaskItem?
    @State private var showArchiveConfirm = false
    @State private var showDeleteConfirm = false
    @State private var actionError: String?

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
                ContentUnavailableView(NexusL10n.tr("project.notFound"), systemImage: "folder.badge.questionmark")
            }
        }
    }

    @ViewBuilder
    private func content(for project: Project) -> some View {
        let board = ProjectBoardMapping.snapshot(from: project)

        VStack(spacing: 0) {
            headerBar(project)

            ProjectVerticalBoardView(
                snapshot: board,
                onAddTask: { status in
                    defaultNewStatus = status
                    isCreatingTask = true
                },
                onEditTask: { editingTaskID = $0 },
                onDeleteTask: { taskID in
                    taskPendingDelete = try? TaskRepository(context: modelContext).fetchTask(id: taskID)
                },
                onMoveToStatus: { taskID, status in
                    _ = commitMove(taskID: taskID, to: status)
                }
            )
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(NexusL10n.tr("project.edit")) { isEditing = true }
                    Button(NexusL10n.tr("calendar.addTask")) {
                        defaultNewStatus = .todo
                        isCreatingTask = true
                    }
                    if project.status == .active {
                        Button(NexusL10n.tr("project.archive"), role: .destructive) {
                            showArchiveConfirm = true
                        }
                    } else {
                        Button(NexusL10n.tr("project.restore")) { restore(project) }
                    }
                    Button(NexusL10n.tr("project.delete"), role: .destructive) {
                        showDeleteConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(NexusL10n.tr("project.actionsA11y"))
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
                    initialStatus: defaultNewStatus
                )
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
            NexusL10n.format("project.archiveNamed", project.name),
            isPresented: $showArchiveConfirm,
            titleVisibility: .visible
        ) {
            Button(NexusL10n.tr("project.archiveShort")) { archive(project) }
            Button(NexusL10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(NexusL10n.tr("project.archiveMessage"))
        }
        .alert(NexusL10n.tr("project.deleteConfirm"), isPresented: $showDeleteConfirm) {
            Button(NexusL10n.tr("common.delete"), role: .destructive) { delete(project) }
            Button(NexusL10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            let count = (project.tasks ?? []).count
            if count == 1 {
                Text(NexusL10n.format("project.deleteMessageOne", project.name))
            } else {
                Text(NexusL10n.format("project.deleteMessage", project.name, count))
            }
        }
        .alert(
            NexusL10n.tr("task.deleteConfirm"),
            isPresented: Binding(
                get: { taskPendingDelete != nil },
                set: { if !$0 { taskPendingDelete = nil } }
            ),
            presenting: taskPendingDelete
        ) { task in
            Button(NexusL10n.tr("common.delete"), role: .destructive) { deleteTask(task) }
            Button(NexusL10n.tr("common.cancel"), role: .cancel) {}
        } message: { task in
            let descendants = TaskRepository(context: modelContext).descendantCount(of: task)
            if descendants > 0 {
                if descendants == 1 {
                    Text(NexusL10n.tr("task.deleteAlsoSubtasksOne"))
                } else {
                    Text(NexusL10n.format("task.deleteAlsoSubtasks", descendants))
                }
            } else {
                Text(NexusL10n.format("task.deleteNamed", task.title))
            }
        }
        .alert(
            NexusL10n.tr("common.somethingWrong"),
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button(NexusL10n.tr("common.ok"), role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    @ViewBuilder
    private func headerBar(_ project: Project) -> some View {
        let roots = (project.tasks ?? []).filter(\.isRoot)
        let openCount = roots.filter { $0.status != .done }.count
        HStack(alignment: .center, spacing: NexusSpacing.sm) {
            NexusProjectGlyph(systemName: project.icon, colorHex: project.colorHex, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(NexusL10n.plural("widget.openTasksCount", count: openCount))
                    .font(NexusTypography.metadata)
                    .foregroundStyle(.secondary)
                if project.status == .archived {
                    Text(NexusL10n.tr("project.archivedBadge"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if !project.projectDescription.isEmpty {
                    Text(project.projectDescription)
                        .font(NexusTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NexusSpacing.md)
        .padding(.top, NexusSpacing.xs)
        .padding(.bottom, NexusSpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    @discardableResult
    private func commitMove(taskID: UUID, to status: TaskStatus) -> Bool {
        let repo = TaskRepository(context: modelContext)
        do {
            let previousStatus = try repo.fetchTask(id: taskID)?.status
            let didWrite = try repo.move(taskID: taskID, to: status, before: nil)
            if didWrite {
                NexusHaptics.taskStatusChanged(crossStatus: previousStatus != status)
            }
            return didWrite
        } catch {
            actionError = UserFacingError.message(for: error)
            return false
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
