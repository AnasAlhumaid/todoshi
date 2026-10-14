import SwiftUI
import SwiftData
import TodoshiCore

struct RootView: View {
    @Bindable var router: AppRouter
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSessionController.self) private var authSession
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var accessLossToast: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent(.dashboard) {
                NavigationStack(path: $router.dashboardPath) {
                    DashboardView()
                        .navigationDestination(for: AppRoute.self) { route in
                            routeDestination(route)
                        }
                }
            }

            tabContent(.projects) {
                NavigationStack(path: $router.projectsPath) {
                    ProjectsListView()
                        .navigationDestination(for: AppRoute.self) { route in
                            routeDestination(route)
                        }
                }
            }

            tabContent(.calendar) {
                NavigationStack(path: $router.calendarPath) {
                    CalendarView()
                        .navigationDestination(for: AppRoute.self) { route in
                            routeDestination(route)
                        }
                }
            }

            tabContent(.search) {
                NavigationStack(path: $router.searchPath) {
                    SearchView()
                        .navigationDestination(for: AppRoute.self) { route in
                            routeDestination(route)
                        }
                }
            }

            // Settings has no bar slot (reached from Home) but stays a root so sign-out and
            // account deletion can land on it. sessionUIEpoch rebuilds it at root on sign-out.
            tabContent(.settings) {
                NavigationStack {
                    SettingsView()
                        .navigationDestination(for: AppRoute.self) { route in
                            routeDestination(route)
                        }
                }
                .id("settings-auth-\(authSession.sessionUIEpoch)")
            }

            TodoshiTabBar(
                selection: $router.selectedTab,
                onAdd: { router.presentQuickAdd() }
            )
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .tint(TodoshiBrand.accent)
        .onAppear {
            logRootAuthUI()
        }
        .environment(router)
        .sheet(isPresented: $router.isPresentingQuickAdd, onDismiss: {
            router.quickAddPreselectedProjectID = nil
        }) {
            NavigationStack {
                QuickAddView(preselectedProjectID: router.quickAddPreselectedProjectID)
                    .id(router.quickAddPreselectedProjectID?.uuidString ?? "quick-add-generic")
            }
            // Sheets do not reliably inherit the in-app language direction.
            .environment(\.layoutDirection, layoutDirection)
            .presentationDetents([.height(230), .medium])
            .presentationCornerRadius(28)
        }
        .sheet(isPresented: Binding(
            get: { authSession.isPresentingAuthenticationSheet },
            set: { authSession.isPresentingAuthenticationSheet = $0 }
        )) {
            AuthenticationView()
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
        .sheet(isPresented: Binding(
            get: { router.isPresentingInvitePreview },
            set: { if !$0 { router.dismissInvitePreview() } }
        )) {
            if let token = router.pendingInviteTokenForPreview {
                ProjectInvitePreviewView(token: token)
                    .environment(router)
                    .environment(authSession)
            }
        }
        .onChange(of: authSession.state) { oldState, newState in
            handleAuthStateChange(newState, previous: oldState)
        }
        .onChange(of: authSession.sessionUIEpoch) { _, _ in
            // Epoch bump (sign-out / deletion) must keep Settings selected and auth sheet closed.
            guard case .signedOut = authSession.state else { return }
            authSession.isPresentingAuthenticationSheet = false
            if router.selectedTab != .settings {
                router.resetAuthenticatedNavigation(selectSettings: true)
            }
        }
        .onChange(of: authSession.currentSession?.user.id) { _, newValue in
            guard newValue != nil else { return }
            resumePendingInviteIfNeeded()
        }
        .onAppear {
            resumePendingInviteIfNeeded()
        }
        .todoshiToast(message: $accessLossToast)
        .onReceive(NotificationCenter.default.publisher(for: SharedProjectAccessLossCenter.notification)) { note in
            guard let message = note.userInfo?[SharedProjectAccessLossCenter.UserInfoKey.message] as? String else {
                return
            }
            if let projectIDRaw = note.userInfo?[SharedProjectAccessLossCenter.UserInfoKey.projectID] as? String,
               let projectID = UUID(uuidString: projectIDRaw) {
                router.dashboardPath.removeAll { route in
                    switch route {
                    case .project(let id), .projectMembers(let id):
                        return id == projectID
                    case .projectEditor(let id):
                        return id == projectID
                    default:
                        return false
                    }
                }
                router.projectsPath.removeAll { route in
                    if case .project(let id) = route { return id == projectID }
                    return false
                }
                router.calendarPath.removeAll { route in
                    if case .project(let id) = route { return id == projectID }
                    return false
                }
                router.searchPath.removeAll { route in
                    if case .project(let id) = route { return id == projectID }
                    return false
                }
            }
            accessLossToast = message
        }
    }

    /// Keeps every tab's navigation state alive while only the selected one is visible.
    private func tabContent<Content: View>(
        _ tab: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isSelected = router.selectedTab == tab
        return content()
            // Content margins reach every scroll view in the stack, including pushed screens,
            // so the last row can scroll clear of the floating bar.
            .contentMargins(.bottom, TodoshiTabBar.reservedHeight, for: .scrollContent)
            .contentMargins(.bottom, TodoshiTabBar.reservedHeight, for: .scrollIndicators)
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }

    private func handleAuthStateChange(_ newState: AuthenticationState, previous: AuthenticationState) {
        logRootAuthUI()
        guard RootAuthPresentationPolicy.shouldResetAuthenticatedNavigation(for: newState) else {
            return
        }
        // Explicit terminal hierarchy reset — do not rely on Profile.dismiss() alone.
        // 1) Close Authentication sheet binding
        // 2) Clear all tab paths / transient sheets
        // 3) Select Settings tab
        // sessionUIEpoch (bumped in AuthSession) rebuilds Settings NavigationStack at root,
        // destroying Profile + AccountDeletion sheet.
        authSession.isPresentingAuthenticationSheet = false
        // Only an actual sign-out or deletion lands on Settings; a signed-out launch stays on Home.
        let wasSignedIn: Bool
        if case .signedIn = previous { wasSignedIn = true } else { wasSignedIn = false }
        router.resetAuthenticatedNavigation(selectSettings: wasSignedIn)
        #if DEBUG
        TodoshiDiagnostics.note(
            "[AccountDeletionUI] Settings root selectedTab=\(router.selectedTab.rawValue) epoch=\(authSession.sessionUIEpoch)"
        )
        #endif
    }

    private func logRootAuthUI() {
        #if DEBUG
        let label: String
        switch authSession.state {
        case .loading: label = "loading"
        case .signedOut: label = "signedOut"
        case .signedIn: label = "signedIn"
        }
        TodoshiDiagnostics.note("[RootAuthUI] authInstance=\(authSession.instanceID) state=\(label)")
        #endif
    }

    private func resumePendingInviteIfNeeded() {
        guard case .authenticated = authSession.authRequirement else { return }
        guard let token = authSession.pendingInviteToken else { return }
        // Only consume once authenticated so preview can open without reopening the link.
        _ = authSession.consumePendingInviteToken()
        router.presentInvitePreview(token: token)
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
                    title: TodoshiL10n.tr("common.task"),
                    systemImage: "checklist",
                    message: TodoshiL10n.tr("task.requiredProject")
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
        case .projectMembers(let id):
            ProjectMembersView(projectID: id, projectName: "")
        case .allProjects:
            ProjectsListView()
        }
    }
}
