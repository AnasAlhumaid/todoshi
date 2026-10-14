import SwiftUI
import SwiftData
import UserNotifications
import TodoshiCore

@main
struct TodoshiApp: App {
    private let launch: AppLaunchResult
    @State private var router = AppRouter()
    @State private var authSession = AuthSessionController()
    @State private var appLanguage = AppLanguageController()
    private let notificationHandler = NotificationResponseHandler()

    init() {
        FirebaseBootstrap.configureIfAvailable()
        AppGroupMigration.migrateIfNeeded()
        AppLanguageStore.migrateIfNeeded()
        do {
            let container = try ModelContainerFactory.makeProductionContainer()
            launch = .ready(container)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-TodoshiDemoData") {
                Self.insertDemoData(into: container.mainContext)
            }
            #endif
        } catch {
            TodoshiDiagnostics.failure("store_open")
            launch = .failed(UserFacingError.message(for: error))
        }
    }

    #if DEBUG
    /// Arabic sample projects for design review screenshots. Debug builds only; inserted once.
    @MainActor
    private static func insertDemoData(into context: ModelContext) {
        let marker = "تودوشي"
        let existing = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        guard !existing.contains(where: { $0.name == marker }) else { return }

        let calendar = Calendar.current
        let today = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: .now) ?? .now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        let sunday = calendar.date(byAdding: .day, value: 4, to: today)
        var position = FractionalPosition.initial()
        func nextPosition() -> Double {
            position = FractionalPosition.after(position)
            return position
        }

        let work = Project(name: marker, icon: "briefcase.fill", colorHex: "#E5487D", position: nextPosition())
        let nasaq = Project(name: "نسق", icon: "laptopcomputer", colorHex: "#3E8BEB", position: nextPosition())
        let home = Project(name: "مقاضي البيت", icon: "cart.fill", colorHex: "#30A46C", position: nextPosition())
        home.projectType = .checklist
        [work, nasaq, home].forEach(context.insert)

        let login = TaskItem(
            title: "صفحة تسجيل الدخول",
            taskDescription: "تصميم شاشة الدخول بأبل وقوقل، مع رسالة خطأ واضحة لما يفشل الاتصال.",
            status: .inProgress, dueDate: yesterday, position: nextPosition(), project: work
        )
        let store = TaskItem(title: "كتابة وصف المتجر", dueDate: sunday, position: nextPosition(), project: work)
        let sync = TaskItem(title: "إصلاح مزامنة الإشعارات", priority: .urgent, position: nextPosition(), project: work)
        let send = TaskItem(title: "إرسال التصميم للعميل", dueDate: yesterday, position: nextPosition(), project: work)
        let widget = TaskItem(title: "مراجعة الودجت", dueDate: today, position: nextPosition(), project: nasaq)
        let meeting = TaskItem(title: "اجتماع الفريق", status: .done, dueDate: today, position: nextPosition(), project: nasaq)
        meeting.applyStatus(.done)
        [login, store, sync, send, widget, meeting].forEach(context.insert)

        for (index, title) in ["الرسم المبدئي", "ربط Firebase", "اختبار حالات الخطأ"].enumerated() {
            let child = TaskItem(title: title, position: nextPosition(), project: work, parentTask: login)
            if index == 0 { child.applyStatus(.done) }
            context.insert(child)
        }
        for (index, title) in ["حليب", "خبز", "بيض", "رز", "قهوة"].enumerated() {
            let item = TaskItem(title: title, dueDate: index == 0 ? today : nil, position: nextPosition(), project: home)
            if index >= 3 { item.applyStatus(.done) }
            context.insert(item)
        }
        try? context.save()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            switch launch {
            case .ready(let container):
                RootView(router: router)
                    .fontDesign(.rounded)
                    .modelContainer(container)
                    .environment(authSession)
                    .environment(appLanguage)
                    .environment(\.locale, appLanguage.resolvedLocale)
                    .environment(\.layoutDirection, appLanguage.layoutDirection)
                    .id(appLanguage.preference.rawValue)
                    .onAppear {
                        configureNotifications()
                        authSession.startListening()
                        SharedProjectSyncService.shared.bind(modelContext: container.mainContext)
                        #if DEBUG
                        TodoshiDiagnostics.note(
                            "[RootAuthUI] authInstance=\(authSession.instanceID) state=starting"
                        )
                        #endif
                    }
                    .onOpenURL { url in
                        if authSession.handleIncomingURL(url) {
                            return
                        }
                        if let link = TodoshiDeepLink(url: url), case .invite(let token) = link {
                            handleInviteDeepLink(token: token)
                            return
                        }
                        _ = router.handle(url: url)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: TodoshiDataChangeCenter.notification)) { note in
                        if let event = TodoshiDataChangeCenter.event(from: note.userInfo) {
                            WidgetReloadCoordinator.reload(for: event)
                            if WidgetReloadClassifier.shouldReconcileNotifications(for: event) {
                                NotificationCoordinator.shared.handleDataChange(context: container.mainContext)
                            }
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .todoshiAppLanguageDidChange)) { _ in
                        WidgetReloadCoordinator.reloadAll()
                        NotificationCoordinator.shared.reconcile(context: container.mainContext, force: true)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                        NotificationCoordinator.shared.reconcile(context: container.mainContext)
                        Task { await SharedProjectSyncService.shared.resumeListeningIfNeeded() }
                    }
                    .task {
                        NotificationCoordinator.shared.reconcile(context: container.mainContext, force: true)
                        scheduleOrphanResourceCleanup(container: container)
                    }
            case .failed(let message):
                StoreUnavailableView(message: message)
                    .environment(appLanguage)
                    .environment(\.locale, appLanguage.resolvedLocale)
                    .environment(\.layoutDirection, appLanguage.layoutDirection)
            }
        }
    }

    private func configureNotifications() {
        notificationHandler.onOpenURL = { [router] url in
            _ = router.handle(url: url)
        }
        UNUserNotificationCenter.current().delegate = notificationHandler
    }

    private func handleInviteDeepLink(token: String) {
        switch authSession.authRequirement {
        case .requiresAuthentication:
            authSession.rememberPendingInviteToken(token)
            authSession.presentAuthenticationSheet()
        case .authenticated:
            router.presentInvitePreview(token: token)
        }
    }

    /// Conservative once-per-launch cleanup of unreferenced managed resource files (age ≥ 24h).
    private func scheduleOrphanResourceCleanup(container: ModelContainer) {
        let context = ModelContext(container)
        Task.detached(priority: .utility) {
            do {
                let removed = try TaskResourceRepository(context: context).cleanupOrphans(
                    olderThan: 24 * 60 * 60,
                    now: .now
                )
                if removed > 0 {
                    TodoshiDiagnostics.note("orphan_cleanup removed=\(removed)")
                }
            } catch {
                TodoshiDiagnostics.failure("orphan_cleanup")
            }
        }
    }
}

private enum AppLaunchResult {
    case ready(ModelContainer)
    case failed(String)
}

private struct StoreUnavailableView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(TodoshiL10n.tr("store.cantOpenTitle"), systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(message)
        }
        .padding()
    }
}
