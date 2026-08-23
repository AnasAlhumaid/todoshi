import SwiftUI
import SwiftData
import NexusCore

struct TaskFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: TaskFormViewModel
    @State private var showLabelPicker = false

    init(
        context: ModelContext,
        projectID: UUID,
        taskID: UUID? = nil,
        initialStatus: TaskStatus = .todo,
        parentTaskID: UUID? = nil
    ) {
        _viewModel = State(
            initialValue: TaskFormViewModel(
                context: context,
                projectID: projectID,
                taskID: taskID,
                initialStatus: initialStatus,
                parentTaskID: parentTaskID
            )
        )
    }

    init(
        context: ModelContext,
        projectID: UUID,
        initialDueDate: Date
    ) {
        _viewModel = State(
            initialValue: TaskFormViewModel(
                context: context,
                projectID: projectID,
                initialStatus: .todo,
                initialDueDate: initialDueDate
            )
        )
    }

    var body: some View {
        Form {
            if let parentTitle = viewModel.parentTitle, viewModel.isCreatingSubtask || viewModel.draft.parentTaskID != nil {
                Section {
                    LabeledContent(SubtaskStrings.subtaskOf) {
                        Text(parentTitle)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(SubtaskStrings.parentTask)
                }
            }

            Section {
                TextField(NexusL10n.tr("task.titlePlaceholder"), text: $viewModel.draft.title)
            }

            Section(NexusL10n.tr("form.planning")) {
                Picker(NexusL10n.tr("common.status"), selection: $viewModel.draft.status) {
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                .onChange(of: viewModel.draft.status) { _, newStatus in
                    if newStatus == .done, viewModel.draft.hasReminder {
                        viewModel.setReminderEnabled(false)
                    }
                }
                Picker(NexusL10n.tr("common.priority"), selection: $viewModel.draft.priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
                Toggle(NexusL10n.tr("common.dueDate"), isOn: $viewModel.draft.hasDueDate)
                if viewModel.draft.hasDueDate {
                    DatePicker(
                        NexusL10n.tr("common.dueDate"),
                        selection: Binding(
                            get: { viewModel.draft.dueDate ?? .now },
                            set: { viewModel.draft.dueDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                }
            }

            Section {
                Toggle(
                    NexusL10n.tr("common.reminder"),
                    isOn: Binding(
                        get: { viewModel.draft.hasReminder },
                        set: { viewModel.setReminderEnabled($0) }
                    )
                )
                .accessibilityLabel(NexusL10n.tr("reminder.a11y"))
                .disabled(viewModel.draft.status == .done)

                if viewModel.draft.hasReminder {
                    DatePicker(
                        NexusL10n.tr("reminder.remindMe"),
                        selection: Binding(
                            get: {
                                viewModel.draft.reminderDate
                                    ?? TaskReminderValidation.defaultReminderDate(
                                        dueDate: viewModel.draft.resolvedDueDate
                                    )
                            },
                            set: { viewModel.draft.reminderDate = $0 }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .accessibilityLabel(NexusL10n.tr("reminder.a11yDate"))

                    Button(NexusL10n.tr("reminder.clear"), role: .destructive) {
                        viewModel.setReminderEnabled(false)
                    }

                    if viewModel.authorizationState == .denied {
                        Text(NotificationStrings.deniedMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(NotificationStrings.openSettings) {
                            NotificationAuthorizationManager.openSystemSettings()
                        }
                    }
                }

                if let reminderMessage = viewModel.reminderValidationMessage {
                    Text(reminderMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text(NexusL10n.tr("common.reminder"))
            }

            if viewModel.showsRecurrenceControls {
                Section {
                    Toggle(
                        TaskRecurrenceStrings.repeatSection,
                        isOn: Binding(
                            get: { viewModel.draft.recurrenceEnabled },
                            set: { viewModel.draft.setRecurrenceEnabled($0) }
                        )
                    )
                    .accessibilityLabel(TaskRecurrenceStrings.repeatSection)

                    if viewModel.draft.recurrenceEnabled {
                        Picker(TaskRecurrenceStrings.repeatSection, selection: $viewModel.draft.recurrenceKind) {
                            ForEach(TaskRecurrenceKind.allCases, id: \.self) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                        .accessibilityLabel(TaskRecurrenceStrings.repeatSection)

                        if viewModel.draft.recurrenceKind.usesCustomInterval {
                            Stepper(
                                value: $viewModel.draft.recurrenceInterval,
                                in: 1...TaskRecurrencePolicy.maxInterval
                            ) {
                                Text("\(TaskRecurrenceStrings.interval): \(viewModel.draft.recurrenceInterval)")
                            }
                            .accessibilityLabel(TaskRecurrenceStrings.interval)
                            .accessibilityValue("\(viewModel.draft.recurrenceInterval)")
                        }

                        Text(viewModel.draft.recurrenceSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(viewModel.draft.recurrenceSummary)

                        if viewModel.draft.recurrenceValidationIssue != nil {
                            Text(TaskRecurrenceStrings.dueDateRequired)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .accessibilityLabel(TaskRecurrenceStrings.dueDateRequired)
                        }
                    }
                } header: {
                    Text(TaskRecurrenceStrings.repeatSection)
                } footer: {
                    if viewModel.draft.recurrenceEnabled {
                        Text(viewModel.draft.recurrenceSummary)
                    }
                }
            }

            Section {
                if !viewModel.selectedLabelSummaries.isEmpty {
                    FlowLabelChips(summaries: viewModel.selectedLabelSummaries)
                }
                Button(viewModel.selectedLabelSummaries.isEmpty ? LabelStrings.addLabel : LabelStrings.editSelected) {
                    showLabelPicker = true
                }
            } header: {
                Text(LabelStrings.labels)
            } footer: {
                Text(LabelStrings.formHint)
            }

            TaskFormChecklistSection(
                items: $viewModel.draft.checklistItems,
                focusedID: Binding(
                    get: { viewModel.focusedChecklistDraftID },
                    set: { viewModel.focusedChecklistDraftID = $0 }
                ),
                onAdd: { viewModel.addChecklistDraft() },
                onDelete: { viewModel.deleteChecklistDraft(id: $0) },
                onMove: { viewModel.moveChecklistDrafts(from: $0, to: $1) }
            )
            .environment(\.editMode, .constant(.active))

            TaskFormResourcesSection(viewModel: viewModel)

            Section(NexusL10n.tr("common.description")) {
                TextField(NexusL10n.tr("task.descriptionPlaceholder"), text: $viewModel.draft.taskDescription, axis: .vertical)
                    .lineLimit(2...5)
            }

            Section(NexusL10n.tr("common.notes")) {
                TextField(NexusL10n.tr("common.notes"), text: $viewModel.draft.notes, axis: .vertical)
                    .lineLimit(3...8)
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            if let warning = viewModel.schedulingWarning {
                Section {
                    Text(warning)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.refreshAuthorization()
            viewModel.reloadLabels()
        }
        .sheet(isPresented: $showLabelPicker, onDismiss: {
            viewModel.reloadLabels()
        }) {
            NavigationStack {
                LabelPickerView(selectedIDs: $viewModel.draft.labelIDs)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(NexusL10n.tr("common.done")) { showLabelPicker = false }
                                .fontWeight(.semibold)
                        }
                    }
            }
        }
        .alert(NotificationStrings.enableTitle, isPresented: $viewModel.showPermissionExplainer) {
            Button(NotificationStrings.notNow, role: .cancel) {}
            Button(NotificationStrings.allow) {
                Task { await viewModel.requestPermissionFromExplainer() }
            }
        } message: {
            Text(NotificationStrings.enableMessage)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NexusL10n.tr("common.cancel")) {
                    viewModel.discardStagedResourceFiles()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(NexusL10n.tr("common.save")) {
                    if viewModel.save() {
                        dismiss()
                    }
                }
                .disabled(!viewModel.canSave)
                .fontWeight(.semibold)
            }
        }
    }
}

private struct FlowLabelChips: View {
    let summaries: [LabelSummary]

    var body: some View {
        // Simple wrapping via flexible layout for form sections
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(summaries.chunked(into: 3)), id: \.first!.id) { row in
                HStack(spacing: 6) {
                    ForEach(row) { item in
                        LabelChipView(name: item.name, colorHex: item.colorHex, compact: false)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        var result: [[Element]] = []
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            result.append(Array(self[index..<end]))
            index = end
        }
        return result
    }
}
