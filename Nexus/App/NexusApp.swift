import SwiftUI
import SwiftData
import UserNotifications
import NexusCore

@main
struct NexusApp: App {
    private let launch: AppLaunchResult
    @State private var router = AppRouter()
    private let notificationHandler = NotificationResponseHandler()

    init() {
        do {
            let container = try ModelContainerFactory.makeProductionContainer()
            launch = .ready(container)
        } catch {
            NexusDiagnostics.failure("store_open")
            launch = .failed(UserFacingError.message(for: error))
        }
    }

    var body: some Scene {
        WindowGroup {
            switch launch {
            case .ready(let container):
                RootView(router: router)
                    .modelContainer(container)
                    .onAppear {
                        configureNotifications()
                    }
                    .onOpenURL { url in
                        _ = router.handle(url: url)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NexusDataChangeCenter.notification)) { note in
                        if let event = NexusDataChangeCenter.event(from: note.userInfo) {
                            WidgetReloadCoordinator.reload(for: event)
                            if WidgetReloadClassifier.shouldReconcileNotifications(for: event) {
                                NotificationCoordinator.shared.handleDataChange(context: container.mainContext)
                            }
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                        NotificationCoordinator.shared.reconcile(context: container.mainContext)
                    }
                    .task {
                        NotificationCoordinator.shared.reconcile(context: container.mainContext, force: true)
                        scheduleOrphanResourceCleanup(container: container)
                    }
            case .failed(let message):
                StoreUnavailableView(message: message)
            }
        }
    }

    private func configureNotifications() {
        notificationHandler.onOpenURL = { [router] url in
            _ = router.handle(url: url)
        }
        UNUserNotificationCenter.current().delegate = notificationHandler
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
                    NexusDiagnostics.note("orphan_cleanup removed=\(removed)")
                }
            } catch {
                NexusDiagnostics.failure("orphan_cleanup")
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
            Label(NexusL10n.tr("store.cantOpenTitle"), systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(message)
        }
        .padding()
    }
}
