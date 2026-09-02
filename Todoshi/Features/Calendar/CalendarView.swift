import SwiftUI
import SwiftData
import NexusCore
import UIKit

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var projects: [Project]

    @AppStorage(CalendarPreferences.modeKey) private var modeRaw: String = CalendarPreferences.defaultMode.rawValue
    @AppStorage(CalendarPreferences.showCompletedKey) private var showCompleted: Bool = false

    @State private var viewModel: CalendarViewModel?
    @State private var showCreateSheet = false
    @State private var showCreateProject = false
    @State private var createProjectID: UUID?
    @State private var rescheduleTaskID: UUID?
    @State private var rescheduleDraftDate: Date = .now

    private var mode: CalendarMode {
        CalendarMode(rawValue: modeRaw) ?? .week
    }

    private var calendar: Calendar { .autoupdatingCurrent }

    /// Rebuild token: data + selection + mode + day boundary.
    private var sources: [CalendarTaskSource] {
        _ = viewModel?.dayBoundaryToken
        return CalendarMapping.taskSources(projects: projects)
    }

    private var activeProjects: [Project] {
        projects.filter { $0.status == .active }
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView()
                    .onAppear {
                        viewModel = CalendarViewModel(context: modelContext)
                    }
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: CalendarViewModel) -> some View {
        let selected = viewModel.selectedDate
        let now = viewModel.dayBoundaryToken
        let agenda = CalendarScheduleBuilder.dayAgenda(
            tasks: sources,
            selectedDay: selected,
            includeCompleted: showCompleted,
            now: now,
            calendar: calendar
        )
        let weekSummaries = CalendarScheduleBuilder.weekSummaries(
            containing: selected,
            tasks: sources,
            now: now,
            calendar: calendar
        )
        let monthCells = CalendarScheduleBuilder.monthCells(
            containing: selected,
            tasks: sources,
            now: now,
            calendar: calendar
        )

        List {
            Section {
                Picker(CalendarStrings.calendar, selection: modeBinding) {
                    ForEach(CalendarMode.allCases) { item in
                        Text(item.title).tag(item.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

                CalendarHeaderView(
                    mode: mode,
                    selectedDate: selected,
                    calendar: calendar,
                    onPrevious: { navigate(-1, viewModel: viewModel) },
                    onNext: { navigate(1, viewModel: viewModel) },
                    onToday: { viewModel.goToToday() }
                )
                .listRowBackground(Color.clear)

                switch mode {
                case .day:
                    EmptyView()
                case .week:
                    WeekStripView(
                        summaries: weekSummaries,
                        selectedDate: selected,
                        now: now,
                        calendar: calendar,
                        onSelect: { viewModel.select($0) }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowBackground(Color.clear)
                case .month:
                    MonthGridView(
                        cells: monthCells,
                        selectedDate: selected,
                        now: now,
                        calendar: calendar,
                        onSelect: { viewModel.select($0) }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                }
            }

            DayAgendaView(
                agenda: agenda,
                selectedDay: selected,
                onComplete: { viewModel.complete(taskID: $0) },
                onReopen: { viewModel.reopen(taskID: $0) },
                onChangeDueDate: { beginReschedule(taskID: $0) },
                onRemoveDueDate: { viewModel.updateDueDate(taskID: $0, dueDate: nil) },
                onAddTask: { beginCreateTask(selectedDate: selected) }
            )

            Section {
                NavigationLink(value: AppRoute.upcoming) {
                    Text(CalendarStrings.upcoming)
                }
                NavigationLink(value: AppRoute.unscheduled) {
                    Text(CalendarStrings.unscheduled)
                }
            }

            Section {
                Toggle(CalendarStrings.showCompleted, isOn: $showCompleted)
            } footer: {
                Text(CalendarStrings.includeCompletedHint)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(CalendarStrings.calendar)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(CalendarStrings.today) { viewModel.goToToday() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    beginCreateTask(selectedDate: selected)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(CalendarStrings.addTask)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            NavigationStack {
                if let createProjectID {
                    TaskFormView(
                        context: modelContext,
                        projectID: createProjectID,
                        initialDueDate: selected
                    )
                } else {
                    ContentUnavailableView(
                        CalendarStrings.createProjectFirst,
                        systemImage: "folder.badge.plus",
                        description: Text(CalendarStrings.createProjectFirstMessage)
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(NexusL10n.tr("common.close")) { showCreateSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(NexusL10n.tr("common.createProject")) {
                                showCreateSheet = false
                                showCreateProject = true
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateProject) {
            NavigationStack {
                ProjectFormView(context: modelContext)
            }
        }
        .sheet(item: Binding(
            get: { rescheduleTaskID.map { RescheduleIdentity(id: $0) } },
            set: { rescheduleTaskID = $0?.id }
        )) { item in
            NavigationStack {
                Form {
                    DatePicker(
                        CalendarStrings.changeDueDate,
                        selection: $rescheduleDraftDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                .navigationTitle(CalendarStrings.changeDueDate)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NexusL10n.tr("common.cancel")) { rescheduleTaskID = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(NexusL10n.tr("common.save")) {
                            viewModel.updateDueDate(taskID: item.id, dueDate: rescheduleDraftDate)
                            rescheduleTaskID = nil
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
                get: { viewModel.actionError != nil },
                set: { if !$0 { viewModel.actionError = nil } }
            )
        ) {
            Button(NexusL10n.tr("common.ok"), role: .cancel) {}
        } message: {
            Text(viewModel.actionError ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.refreshDayBoundary()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            viewModel.refreshDayBoundary()
        }
        .task(id: viewModel.dayBoundaryToken) {
            let delay = viewModel.secondsUntilNextMidnight()
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if !Task.isCancelled {
                viewModel.refreshDayBoundary()
            }
        }
    }

    private var modeBinding: Binding<String> {
        Binding(
            get: { modeRaw },
            set: { modeRaw = $0 }
        )
    }

    private func navigate(_ direction: Int, viewModel: CalendarViewModel) {
        switch mode {
        case .day:
            viewModel.shiftDay(direction)
        case .week:
            viewModel.shiftWeek(direction)
        case .month:
            viewModel.shiftMonth(direction)
        }
    }

    private func beginCreateTask(selectedDate: Date) {
        if let first = activeProjects.sorted(by: { $0.position < $1.position }).first {
            createProjectID = first.id
            showCreateSheet = true
        } else {
            createProjectID = nil
            showCreateSheet = true
        }
        _ = selectedDate
    }

    private func beginReschedule(taskID: UUID) {
        if let task = try? TaskRepository(context: modelContext).fetchTask(id: taskID) {
            rescheduleDraftDate = task.dueDate ?? viewModel?.selectedDate ?? .now
        } else {
            rescheduleDraftDate = viewModel?.selectedDate ?? .now
        }
        rescheduleTaskID = taskID
    }
}

private struct RescheduleIdentity: Identifiable {
    let id: UUID
}
