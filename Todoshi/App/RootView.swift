import SwiftUI
import SwiftData
import NexusCore

struct RootView: View {
    @Bindable var router: AppRouter
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.dashboardPath) {
                DashboardView()
                    .navigationDestination(for: AppRoute.self) { route in
                        routeDestination(route)
                    }
            }
            .tabItem { Label(AppTab.dashboard.title, systemImage: AppTab.dashboard.systemImage) }
            .tag(AppTab.dashboard)

            NavigationStack(path: $router.calendarPath) {
                CalendarView()
                    .navigationDestination(for: AppRoute.self) { route in
                        routeDestination(route)
                    }
            }
            .tabItem { Label(AppTab.calendar.title, systemImage: AppTab.calendar.systemImage) }
            .tag(AppTab.calendar)

            NavigationStack(path: $router.searchPath) {
                SearchView()
                    .navigationDestination(for: AppRoute.self) { route in
                        routeDestination(route)
                    }
            }
            .tabItem { Label(AppTab.search.title, systemImage: AppTab.search.systemImage) }
            .tag(AppTab.search)

            NavigationStack {
                SettingsView()
                    .navigationDestination(for: AppRoute.self) { route in
                        routeDestination(route)
                    }
            }
            .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
            .tag(AppTab.settings)
        }
        .environment(router)
        .sheet(isPresented: $router.isPresentingQuickAdd) {
            NavigationStack {
                QuickAddView()
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $router.isPresentingWidgetProjectPicker) {
            NavigationStack {
                WidgetProjectPickerView(baseProjectID: router.widgetProjectPickerBaseProjectID)
            }
            .presentationDetents([.medium, .large])
            .onDisappear {
                router.dismissWidgetProjectPicker()
            }
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: AppRoute) -> some View {
        switch route {
        case .project(let id):
            ProjectDetailView(projectID: id)
        case .task(let id):
            TaskDetailView(taskID: id)
        case .archivedProjects:
            ArchivedProjectsView()
        case .allOverdue:
            OverdueTasksView()
        case .projectEditor(let id):
            ProjectFormView(context: modelContext, projectID: id)
        case .taskEditor(let projectID, let taskID):
            if let projectID {
                TaskFormView(context: modelContext, projectID: projectID, taskID: taskID)
            } else {
                PlaceholderTabView(
                    title: NexusL10n.tr("common.task"),
                    systemImage: "checklist",
                    message: NexusL10n.tr("task.requiredProject")
                )
            }
        case .quickAdd:
            QuickAddView()
        case .labels:
            LabelsListView()
        case .labelEditor(let id):
            LabelFormView(context: modelContext, labelID: id)
        case .labelTasks(let id):
            LabelTasksView(labelID: id)
        case .upcoming:
            UpcomingTasksView()
        case .unscheduled:
            UnscheduledTasksView()
        case .widgetProjectPicker(let baseID):
            WidgetProjectPickerView(baseProjectID: baseID)
        }
    }
}
