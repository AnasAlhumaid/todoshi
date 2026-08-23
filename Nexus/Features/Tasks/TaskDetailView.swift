import SwiftUI
import SwiftData
import NexusCore

struct TaskDetailView: View {
    let taskID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [TaskItem]

    @State private var isEditing = false
    @State private var subtaskForm: TaskSubtaskFormContext?
    @State private var showDeleteConfirm = false
    @State private var showDeleteChoice = false
    @State private var showPromoteConfirm = false
    @State private var actionError: String?

    init(taskID: UUID) {
        self.taskID = taskID
        let id = taskID
        _tasks = Query(filter: #Predicate<TaskItem> { $0.id == id })
    }

    private var task: TaskItem? { tasks.first }

    var body: some View {
        Group {
            if let task {
                content(for: task)
            } else {
                ContentUnavailableView(NexusL10n.tr("task.notFoundTitle"), systemImage: "checkmark.circle.badge.questionmark")
            }
        }
    }

    @ViewBuilder
    private func content(for task: TaskItem) -> some View {
        let isRoot = task.isRoot
        let childCount = TaskRepository(context: modelContext).descendantCount(of: task)

        List {
            Section {
                Text(task.title)
                    .font(NexusTypography.title)
                HStack(spacing: NexusSpacing.sm) {
                    Text(task.status.displayName)
                        .font(NexusTypography.secondary)
                        .foregroundStyle(.secondary)
                    if task.priority != .none {
                        PriorityBadge(priority: task.priority)
                    }
                    Spacer(minLength: 0)
                }
                DueDateLabel(dueDate: task.dueDate, status: task.status)
                if !isRoot {
                    Text(SubtaskStrings.subtask)
                        .font(NexusTypography.metadata)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(SubtaskStrings.subtask)
                }
            }

            if !task.taskDescription.isEmpty {
                Section(NexusL10n.tr("common.description")) {
                    Text(task.taskDescription)
                }
            }

            TaskDetailChecklistSection(
                taskID: task.id,
                items: task.checklist ?? [],
                onError: { actionError = $0 }
            )

            if isRoot {
                TaskDetailSubtasksSection(
                    parent: task,
                    onError: { actionError = $0 },
                    onAddSubtask: { parentTaskID, projectID in
                        subtaskForm = TaskSubtaskFormContext(
                            parentTaskID: parentTaskID,
                            projectID: projectID
                        )
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
                        .accessibilityLabel(NexusL10n.format("label.chipA11y", label.name, LabelColorCatalog.name(for: label.colorHex)))
                    }
                }
            }

            TaskDetailResourcesSection(
                taskID: task.id,
                resources: task.resources ?? [],
                onError: { actionError = $0 }
            )

            if isRoot, task.isRecurring || task.previousOccurrenceID != nil || task.nextOccurrenceID != nil {
                recurrenceSection(for: task)
            }

            if let parent = task.parentTask {
                TaskDetailParentContextSection(
                    parent: parent,
                    projectName: parent.project?.name ?? task.project?.name,
                    onPromote: { showPromoteConfirm = true }
                )
            }

            if let reminder = task.reminderDate {
                Section(NexusL10n.tr("common.reminder")) {
                    LabeledContent(NexusL10n.tr("reminder.remindAt")) {
                        Text(reminder, format: .dateTime.day().month().year().hour().minute())
                    }
                }
            }

            if !task.notes.isEmpty {
                Section(NexusL10n.tr("common.notes")) {
                    Text(task.notes)
                }
            }

            Section(NexusL10n.tr("form.metadata")) {
                LabeledContent(NexusL10n.tr("task.created")) {
                    Text(task.createdAt, style: .date)
                }
                LabeledContent(NexusL10n.tr("task.updated")) {
                    Text(task.updatedAt, format: .dateTime.day().month().year().hour().minute())
                }
                if let completedAt = task.completedAt {
                    LabeledContent(NexusL10n.tr("task.completedAt")) {
                        Text(completedAt, format: .dateTime.day().month().year().hour().minute())
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(isRoot ? NexusL10n.tr("common.task") : NexusL10n.tr("task.subtask"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(NexusL10n.tr("common.edit")) { isEditing = true }
                    if isRoot {
                        Menu(NexusL10n.tr("task.moveToStatus")) {
                            ForEach(TaskStatus.allCases, id: \.self) { status in
                                Button(status.displayName) {
                                    move(task, to: status)
                                }
                                .disabled(task.status == status)
                            }
                        }
                    } else {
                        Menu(NexusL10n.tr("task.moveToStatus")) {
                            ForEach(TaskStatus.allCases, id: \.self) { status in
                                Button(status.displayName) {
                                    setChildStatus(task, status)
                                }
                                .disabled(task.status == status)
                            }
                        }
                        Button(SubtaskStrings.promoteToRoot) {
                            showPromoteConfirm = true
                        }
                    }
                    Button(NexusL10n.tr("common.delete"), role: .destructive) {
                        if isRoot, childCount > 0 {
                            showDeleteChoice = true
                        } else {
                            showDeleteConfirm = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(NexusL10n.tr("task.actionsA11y"))
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
            Button(NexusL10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(deletionChoiceMessage(title: task.title, count: childCount))
        }
        .alert(SubtaskStrings.deleteTaskTitle, isPresented: $showDeleteConfirm) {
            Button(NexusL10n.tr("common.delete"), role: .destructive) {
                delete(task, mode: .deleteDescendants)
            }
            Button(NexusL10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            if task.isRecurring || task.recurrenceSeriesID != nil {
                Text("“\(task.title)” will be permanently deleted. \(TaskRecurrenceStrings.thisOccurrenceOnly)")
            } else {
                Text("“\(task.title)” will be permanently deleted.")
            }
        }
        .alert(SubtaskStrings.promoteConfirmTitle, isPresented: $showPromoteConfirm) {
            Button(SubtaskStrings.promoteToRoot) { promote(task) }
            Button(NexusL10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(SubtaskStrings.promoteConfirmMessage)
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

    private func deletionChoiceMessage(title: String, count: Int) -> String {
        let del = SubtaskStrings.deleteWithDescendantsMessage(count: count)
        let promote = SubtaskStrings.deleteWithPromotionMessage(count: count)
        let header = NexusL10n.format("subtasks.hasCount", title, count)
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
        do {
            try TaskRepository(context: modelContext).moveToStatus(task, status)
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    private func setChildStatus(_ task: TaskItem, _ status: TaskStatus) {
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
                labelIDs: nil
            )
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    private func promote(_ task: TaskItem) {
        do {
            try TaskRepository(context: modelContext).promoteToRoot(taskID: task.id)
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    private func delete(_ task: TaskItem, mode: TaskDeletionMode) {
        do {
            try TaskRepository(context: modelContext).delete(task, mode: mode)
            dismiss()
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }
}