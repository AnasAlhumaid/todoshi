import SwiftUI
import SwiftData
import TodoshiCore

// Quick Add intentionally omits checklist editing, parent selection, and resources (Phases 8–10).
// Capture stays root-task-only without attachments.
struct QuickAddView: View {
    var preselectedProjectID: UUID? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage(QuickAddPreferences.lastProjectIDKey) private var lastProjectIDStored: String = ""
    @AppStorage(QuickAddPreferences.showsOptionalFieldsKey) private var showsOptionalFields = false
    @FocusState private var isTitleFocused: Bool
    @State private var showsDatePicker = false

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
        .navigationTitle(TodoshiL10n.tr("quickAdd.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(TodoshiL10n.tr("common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(TodoshiL10n.tr("common.add")) {
                    if let viewModel { submit(viewModel) }
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
                Label(TodoshiL10n.tr("quickAdd.noProjects"), systemImage: "folder.badge.plus")
            } description: {
                Text(TodoshiL10n.tr("quickAdd.noProjectsMessage"))
            } actions: {
                Button(TodoshiL10n.tr("common.createProject")) { isCreatingProject = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            VStack(alignment: .leading, spacing: TodoshiSpacing.md) {
                TextField(
                    TodoshiL10n.tr("quickAdd.placeholder"),
                    text: Binding(
                        get: { viewModel.draft.title },
                        set: { viewModel.draft.title = $0 }
                    )
                )
                .font(.title3.weight(.medium))
                .focused($isTitleFocused)
                .submitLabel(.done)
                .onSubmit { submit(viewModel) }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TodoshiSpacing.xs) {
                        dateChip(viewModel)
                        projectChip(viewModel)
                        if viewModel.selectedProjectType != .checklist {
                            priorityChip(viewModel)
                        }
                    }
                }
                .scrollClipDisabled()

                if showsDatePicker {
                    DatePicker(
                        TodoshiL10n.tr("quickAdd.date.label"),
                        selection: Binding(
                            get: { viewModel.draft.dueDate ?? .now },
                            set: {
                                viewModel.draft.dueDate = $0
                                viewModel.draft.hasDueDate = true
                            }
                        ),
                        displayedComponents: .date
                    )
                    .font(.subheadline)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, TodoshiSpacing.md)
            .padding(.top, TodoshiSpacing.xs)
            .onAppear { isTitleFocused = true }
        }
    }

    private func submit(_ viewModel: QuickAddViewModel) {
        guard viewModel.canSave, viewModel.save() != nil else { return }
        TodoshiHaptics.taskStatusChanged(crossStatus: false)
        dismiss()
    }

    // MARK: Chips

    private func dateChip(_ viewModel: QuickAddViewModel) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func setDue(_ date: Date?) {
            showsDatePicker = false
            viewModel.draft.dueDate = date
            viewModel.draft.hasDueDate = date != nil
        }
        return Menu {
            Button(TodoshiL10n.tr("quickAdd.date.today")) { setDue(today) }
            Button(TodoshiL10n.tr("quickAdd.date.tomorrow")) {
                setDue(calendar.date(byAdding: .day, value: 1, to: today))
            }
            Button(TodoshiL10n.tr("quickAdd.date.nextWeek")) {
                setDue(calendar.date(byAdding: .day, value: 7, to: today))
            }
            Button(TodoshiL10n.tr("quickAdd.date.pick")) {
                viewModel.draft.dueDate = viewModel.draft.dueDate ?? today
                viewModel.draft.hasDueDate = true
                showsDatePicker = true
            }
            if viewModel.draft.hasDueDate {
                Divider()
                Button(TodoshiL10n.tr("quickAdd.date.none"), role: .destructive) { setDue(nil) }
            }
        } label: {
            QuickAddChip(
                title: dueTitle(viewModel),
                systemImage: "calendar",
                isActive: viewModel.draft.hasDueDate
            )
        }
    }

    private func dueTitle(_ viewModel: QuickAddViewModel) -> String {
        guard viewModel.draft.hasDueDate, let due = viewModel.draft.dueDate else {
            return TodoshiL10n.tr("quickAdd.date.label")
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(due) { return TodoshiL10n.tr("quickAdd.date.today") }
        if calendar.isDateInTomorrow(due) { return TodoshiL10n.tr("quickAdd.date.tomorrow") }
        return due.formatted(.dateTime.day().month(.abbreviated).locale(AppLanguageStore.resolvedLocale))
    }

    private func projectChip(_ viewModel: QuickAddViewModel) -> some View {
        let selected = viewModel.activeProjects.first { $0.id == viewModel.draft.projectID }
        return Menu {
            ForEach(viewModel.activeProjects, id: \.id) { project in
                Button {
                    viewModel.selectProject(project.id)
                } label: {
                    if project.id == viewModel.draft.projectID {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
            Divider()
            Button(TodoshiL10n.tr("common.createProject")) { isCreatingProject = true }
        } label: {
            QuickAddChip(
                title: selected?.name ?? TodoshiL10n.tr("common.project"),
                systemImage: "folder.fill",
                isActive: selected != nil,
                tint: selected.map { TodoshiColor.from(hex: $0.colorHex) }
            )
        }
    }

    private func priorityChip(_ viewModel: QuickAddViewModel) -> some View {
        let priority = viewModel.draft.priority
        return Menu {
            ForEach(TaskPriority.allCases, id: \.self) { option in
                Button(option.displayName) { viewModel.draft.priority = option }
            }
        } label: {
            QuickAddChip(
                title: priority == .none ? TodoshiL10n.tr("quickAdd.priority.label") : priority.displayName,
                systemImage: "flag.fill",
                isActive: priority != .none,
                tint: priority == .urgent || priority == .high ? .orange : nil
            )
        }
    }

    private func bootstrap() {
        let stored = lastProjectIDStored.isEmpty ? nil : lastProjectIDStored
        viewModel = QuickAddViewModel(
            context: modelContext,
            lastProjectIDStored: stored,
            preselectedProjectID: preselectedProjectID,
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

private struct QuickAddChip: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    var tint: Color? = nil

    var body: some View {
        let color = tint ?? (isActive ? TodoshiBrand.accent : Color.secondary)
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption)
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, TodoshiSpacing.sm)
        .frame(minHeight: 36)
        .background(color.opacity(isActive ? 0.14 : 0.08), in: Capsule())
    }
}
