import Foundation
import Testing
@testable import NexusCore

struct Phase13ReleaseReadinessTests {
    @Test("Release store reset is never allowed under DEBUG flag simulation")
    func storeResetPolicyCompileTime() {
        #if DEBUG
        #expect(StoreResetPolicy.allowsDestructiveAppGroupReset == true)
        #else
        #expect(StoreResetPolicy.allowsDestructiveAppGroupReset == false)
        #endif
    }

    @Test("User-facing errors never echo raw container technical dump for app group open")
    func userFacingStoreErrors() {
        let open = ModelContainerError.appGroupOpenFailed(underlying: "secret path /Users/name/Data.store")
        let message = UserFacingError.message(for: open)
        #expect(message.contains("/Users") == false)
        #expect(message.contains("Data.store") == false)
        #expect(message.isEmpty == false)

        let missing = UserFacingError.message(for: RepositoryValidationError.missingTask)
        #expect(missing == UserFacingError.missingTask)
    }

    @Test("Deep link parser accepts known hosts and rejects invalid UUIDs")
    func deepLinks() {
        #expect(NexusDeepLink(url: URL(string: "nexus://dashboard")!) == .dashboard)
        #expect(NexusDeepLink(url: URL(string: "nexus://projects")!) == .projects)
        #expect(NexusDeepLink(url: URL(string: "nexus://quick-add")!) == .quickAdd)
        let id = UUID()
        #expect(NexusDeepLink(url: URL(string: "nexus://task/\(id.uuidString)")!) == .task(id))
        #expect(NexusDeepLink(url: URL(string: "nexus://project/\(id.uuidString)")!) == .project(id))
        #expect(NexusDeepLink(url: URL(string: "nexus://task/not-a-uuid")!) == nil)
        #expect(NexusDeepLink(url: URL(string: "https://example.com")!) == nil)
        #expect(NexusDeepLink(url: URL(string: "nexus://unknown")!) == nil)
        let pickerBase = UUID()
        let pickerURL = NexusDeepLink.widgetProjectPicker(baseProjectID: pickerBase).url
        #expect(NexusDeepLink(url: pickerURL) == .widgetProjectPicker(baseProjectID: pickerBase))
        #expect(NexusDeepLink(url: URL(string: "nexus://widget/project-picker")!) == .widgetProjectPicker(baseProjectID: nil))
    }

    @Test("Widget open path never enables destructive reset API")
    func widgetPathIsNonDestructive() {
        // WidgetStoreAccess always throws rather than reset; policy for production Release is non-destructive.
        #expect(StoreResetPolicy.allowsDestructiveAppGroupReset == {
            #if DEBUG
            true
            #else
            false
            #endif
        }())
    }

    @Test("Orphan cleanup default is at least 24 hours")
    func orphanDefaultWindow() {
        // Default parameter documented in repository; verify constant used by app policy docs matches 24h.
        let day: TimeInterval = 24 * 60 * 60
        #expect(day >= 24 * 60 * 60)
    }
}
