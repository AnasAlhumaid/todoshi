import Foundation
import Testing
@testable import TodoshiCore

@Suite("Todoshi rename identifiers")
struct PhaseTodoshiRenameTests {
    @Test("Canonical deep links use todoshi scheme")
    func canonicalDeepLinks() {
        let id = UUID()
        #expect(TodoshiDeepLink.scheme == "todoshi")
        #expect(TodoshiDeepLink.quickAdd().url.absoluteString == "todoshi://quick-add")
        #expect(TodoshiDeepLink.projects.url.absoluteString == "todoshi://projects")
        #expect(TodoshiDeepLink.dashboard.url.absoluteString == "todoshi://dashboard")
        #expect(TodoshiDeepLink.task(id).url.absoluteString == "todoshi://task/\(id.uuidString)")
        #expect(TodoshiDeepLink.project(id).url.absoluteString == "todoshi://project/\(id.uuidString)")
        #expect(
            TodoshiDeepLink.widgetProjectPicker(baseProjectID: id).url.absoluteString
                == "todoshi://widget/project-picker?baseProjectID=\(id.uuidString)"
        )
    }

    @Test("Legacy nexus deep links still parse")
    func legacyDeepLinkParsing() {
        let id = UUID()
        #expect(TodoshiDeepLink(url: URL(string: "nexus://quick-add")!) == .quickAdd(projectID: nil))
        #expect(TodoshiDeepLink(url: URL(string: "nexus://projects")!) == .projects)
        #expect(TodoshiDeepLink(url: URL(string: "nexus://task/\(id.uuidString)")!) == .task(id))
        #expect(TodoshiDeepLink(url: URL(string: "nexus://widget/project-picker")!) == .widgetProjectPicker(baseProjectID: nil))
    }

    @Test("App Group constants target Todoshi identifiers")
    func appGroupConstants() {
        #expect(AppGroupConstants.suiteName == "group.com.anashamad.Todoshi")
        #expect(AppGroupConstants.storeFileName == "Todoshi.store")
        #expect(AppGroupConstants.legacySuiteName == "group.com.anashamad.Nexus")
        #expect(AppGroupConstants.legacyStoreFileName == "Nexus.store")
    }

    @Test("Widget kinds use Todoshi namespace")
    func widgetKinds() {
        #expect(TodoshiWidgetKind.today == "Todoshi.TodayTasks")
        #expect(TodoshiWidgetKind.highPriority == "Todoshi.HighPriority")
        #expect(TodoshiWidgetKind.project == "Todoshi.ProjectTasks")
        #expect(TodoshiWidgetKind.quickAddAccessory == "Todoshi.QuickAddAccessory")
        #expect(TodoshiWidgetKind.todayCountAccessory == "Todoshi.TodayCountAccessory")
    }

    @Test("Notification identifiers are Todoshi-owned with legacy compatibility")
    func notificationIdentifiers() {
        let taskID = UUID()
        #expect(NotificationIdentifier.isTodoshiOwned(NotificationIdentifier.dailySummary))
        #expect(NotificationIdentifier.isTodoshiOwned(NotificationIdentifier.taskReminder(taskID: taskID)))
        #expect(NotificationIdentifier.isTodoshiOwned("\(NotificationIdentifier.legacyTaskReminderPrefix)\(taskID.uuidString)"))
        #expect(NotificationIdentifier.isTodoshiOwned(NotificationIdentifier.legacyDailySummary))
        #expect(NotificationIdentifier.isTodoshiOwned("other") == false)
    }

    @Test("Widget project override reads legacy key once")
    func widgetProjectLegacyKeyMigration() throws {
        let base = UUID()
        let selected = UUID()
        let suite = UserDefaults(suiteName: "group.com.anashamad.Todoshi.rename-tests.\(UUID().uuidString)")!
        let legacyKey = "nexus.widget.project.override.\(base.uuidString)"
        suite.set(selected.uuidString, forKey: legacyKey)

        let resolved = WidgetProjectSelectionStore.overrideID(forBase: base, suite: suite)
        #expect(resolved == selected)
        #expect(suite.string(forKey: legacyKey) == nil)
        #expect(suite.string(forKey: WidgetProjectSelectionStore.storageKey(forBase: base)) == selected.uuidString)
    }
}
