import SwiftUI
import SwiftData
import NexusCore

// Quick Add intentionally omits checklist editing, parent selection, and resources (Phases 8–10).
// Capture stays root-task-only without attachments.
struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage(QuickAddPreferences.lastProjectIDKey) private var lastProjectIDStored: String = ""
    @AppStorage(QuickAddPreferences.showsOptionalFieldsKey) private var showsOptionalFields = false

    @State private var viewModel: QuickAddViewModel?
    @State private var isCreatingProject = false

    var body: some View {
        Group {
            if let viewModel {
                formContent(viewModel)
            } else {
                ProgressView()
                    .onAppear { bootstrap() }
            }
        }
        .navigationTitle(NexusL10n.tr("quickAdd.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NexusL10n.tr("common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(NexusL10n.tr("common.add")) {
                    if viewModel?.save() != nil {
                        dismiss()
                    }
                }
                .disabled(!(viewModel?.canSave ?? false))
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $isCreatingProject, onDismiss: {
            viewModel?.reloadProjects(preferredStoredID: lastProjectIDStored.isEmpty ? nil : lastProjectIDStored)
        }) {
            NavigationStack {
                ProjectFormView(context: modelContext)
            }
        }
    }

    @ViewBuilder
    private func formContent(_ viewModel: QuickAddViewModel) -> some View {
        if !viewModel.hasActiveProjects {
            ContentUnavailableView {
                Label(NexusL10n.tr("quickAdd.noProjects"), systemImage: "folder.badge.plus")
            } description: {
                Text(NexusL10n.tr("quickAdd.noProjectsMessage"))
            } actions: {
                Button(NexusL10n.tr("common.createProject")) { isCreatingProject = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            Form {
                Section(NexusL10n.tr("common.task")) {
                    TextField(NexusL10n.tr("common.title"), text: Binding(
                        get: { viewModel.draft.title },
                        set: { viewModel.draft.title = $0 }
                    ))
                    Picker(NexusL10n.tr("common.project"), selection: Binding(
                        get: { viewModel.draft.projectID },
                        set: { viewModel.draft.projectID = $0 }
                    )) {
                        ForEach(viewModel.activeProjects, id: \.id) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                }

                Section(NexusL10n.tr("form.planning")) {
                    Picker(NexusL10n.tr("common.status"), selection: Binding(
                        get: { viewModel.draft.status },
                        set: { viewModel.draft.status = $0 }
                    )) {
                        ForEach(TaskStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    Picker(NexusL10n.tr("common.priority"), selection: Binding(
                        get: { viewModel.draft.priority },
                        set: { viewModel.draft.priority = $0 }
                    )) {
                        ForEach(TaskPriority.allCases, id: \.self) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                    Toggle(NexusL10n.tr("common.dueDate"), isOn: Binding(
                        get: { viewModel.draft.hasDueDate },
                        set: { viewModel.draft.hasDueDate = $0 }
                    ))
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
                    Toggle(NexusL10n.tr("form.moreDetails"), isOn: $showsOptionalFields)
                    if showsOptionalFields {
                        TextField(NexusL10n.tr("common.description"), text: Binding(
                            get: { viewModel.draft.taskDescription },
                            set: { viewModel.draft.taskDescription = $0 }
                        ), axis: .vertical)
                        .lineLimit(2...4)
                        TextField(NexusL10n.tr("common.notes"), text: Binding(
                            get: { viewModel.draft.notes },
                            set: { viewModel.draft.notes = $0 }
                        ), axis: .vertical)
                        .lineLimit(2...5)
                    }
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .onChange(of: showsOptionalFields) { _, newValue in
                viewModel.draft.showsOptionalFields = newValue
            }
        }
    }

    private func bootstrap() {
        let stored = lastProjectIDStored.isEmpty ? nil : lastProjectIDStored
        viewModel = QuickAddViewModel(
            context: modelContext,
            lastProjectIDStored: stored,
            showsOptionalFields: showsOptionalFields,
            persistLastProjectID: { value in
                lastProjectIDStored = value ?? ""
            },
            readLastProjectID: {
                lastProjectIDStored.isEmpty ? nil : lastProjectIDStored
            }
        )
    }
}
