import SwiftUI
import SwiftData
import NexusCore

struct UnscheduledTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var projects: [Project]
    @State private var actionError: String?
    @State private var assignTaskID: UUID?
    @State private var assignDate: Date = .now

    private var tasks: [CalendarTaskSource] {
        CalendarScheduleBuilder.unscheduledSources(
            tasks: CalendarMapping.taskSources(projects: projects)
        )
    }

    var body: some View {
        List {
            if tasks.isEmpty {
                CalendarEmptyState(
                    systemImage: "tray",
                    title: CalendarStrings.noUnscheduled,
                    message: NexusL10n.tr("calendar.unscheduledEmptyMessage")
                )
            } else {
                Section {
                    ForEach(tasks) { task in
                        NavigationLink(value: AppRoute.task(task.id)) {
                            CalendarUnscheduledRowView(task: task)
                        }
                        .contextMenu {
                            Button(CalendarStrings.changeDueDate) {
                                assignTaskID = task.id
                                assignDate = .now
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(CalendarStrings.changeDueDate) {
                                assignTaskID = task.id
                                assignDate = .now
                            }
                            .tint(.blue)
                        }
                    }
                } footer: {
                    Text(NexusL10n.tr("calendar.unscheduledHint"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(CalendarStrings.unscheduled)
        .sheet(item: Binding(
            get: { assignTaskID.map { AssignIdentity(id: $0) } },
            set: { assignTaskID = $0?.id }
        )) { item in
            NavigationStack {
                Form {
                    DatePicker(
                        CalendarStrings.changeDueDate,
                        selection: $assignDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                .navigationTitle(CalendarStrings.changeDueDate)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NexusL10n.tr("common.cancel")) { assignTaskID = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(NexusL10n.tr("common.save")) {
                            assignDue(taskID: item.id, date: assignDate)
                            assignTaskID = nil
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium])
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

    private func assignDue(taskID: UUID, date: Date) {
        do {
            let repo = TaskRepository(context: modelContext)
            guard let task = try repo.fetchTask(id: taskID) else { return }
            try repo.updateDueDate(task, dueDate: date)
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }
}

private struct AssignIdentity: Identifiable {
    let id: UUID
}
