import Foundation
import Testing
@testable import NexusCore

struct PhaseNavigationSimplificationTests {
    @Test("Primary shell exposes exactly four tabs without projects")
    func primaryTabStructure() {
        #expect(PrimaryNavigationPolicy.tabIdentifiers.count == 4)
        #expect(PrimaryNavigationPolicy.tabIdentifiers == ["dashboard", "calendar", "search", "settings"])
        #expect(PrimaryNavigationPolicy.tabIdentifiers.contains("projects") == false)
    }

    @Test("nexus://projects deep link remains valid and opens Home")
    func projectsDeepLinkCompatibility() {
        let url = URL(string: "nexus://projects")!
        #expect(NexusDeepLink(url: url) == .projects)
        #expect(PrimaryNavigationPolicy.opensHome(for: .projects))
        #expect(NexusDeepLink.projects.url == url)
    }

    @Test("Project deep link remains typed and does not map to legacy projects tab")
    func projectDeepLinkStillTyped() {
        let id = UUID()
        let link = NexusDeepLink.project(id)
        #expect(NexusDeepLink(url: link.url) == link)
        #expect(PrimaryNavigationPolicy.opensHome(for: link) == false)
    }

    @Test("Widget project fallback URL remains nexus://projects")
    func widgetFallbackURL() {
        #expect(NexusDeepLink.projects.url.absoluteString == "nexus://projects")
    }

    @Test("Home toolbar project-management keys resolve in Arabic and English")
    func homeProjectManagementLocalization() {
        let en = Locale(identifier: "en")
        let ar = Locale(identifier: "ar")
        #expect(NexusL10n.tr("home.projectActions", locale: en) == "Project Actions")
        #expect(NexusL10n.tr("home.projectActions", locale: ar) == "إدارة المشاريع")
        #expect(NexusL10n.tr("project.new", locale: en) == "New Project")
        #expect(NexusL10n.tr("project.new", locale: ar) == "مشروع جديد")
        #expect(NexusL10n.tr("project.archivedTitle", locale: en) == "Archived Projects")
        #expect(NexusL10n.tr("project.archivedTitle", locale: ar) == "المشاريع المؤرشفة")
        #expect(NexusL10n.tr("dashboard.createProject", locale: en) == "Create Project")
        #expect(NexusL10n.tr("dashboard.createProject", locale: ar) == "إنشاء مشروع")
    }

    @Test("Dashboard deep link opens Home")
    func dashboardDeepLinkOpensHome() {
        let url = URL(string: "nexus://dashboard")!
        #expect(NexusDeepLink(url: url) == .dashboard)
        #expect(PrimaryNavigationPolicy.opensHome(for: .dashboard))
    }
}
