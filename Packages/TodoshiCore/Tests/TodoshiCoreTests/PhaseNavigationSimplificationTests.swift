import Foundation
import Testing
@testable import TodoshiCore

struct PhaseNavigationSimplificationTests {
    @Test("Primary shell exposes exactly four tabs without projects")
    func primaryTabStructure() {
        #expect(PrimaryNavigationPolicy.tabIdentifiers.count == 4)
        #expect(PrimaryNavigationPolicy.tabIdentifiers == ["dashboard", "calendar", "search", "settings"])
        #expect(PrimaryNavigationPolicy.tabIdentifiers.contains("projects") == false)
    }

    @Test("Legacy nexus://projects deep link remains valid and opens Home")
    func projectsDeepLinkCompatibility() {
        let url = URL(string: "nexus://projects")!
        #expect(TodoshiDeepLink(url: url) == .projects)
        #expect(PrimaryNavigationPolicy.opensHome(for: .projects))
        #expect(TodoshiDeepLink.projects.url.absoluteString == "todoshi://projects")
    }

    @Test("Project deep link remains typed and does not map to legacy projects tab")
    func projectDeepLinkStillTyped() {
        let id = UUID()
        let link = TodoshiDeepLink.project(id)
        #expect(TodoshiDeepLink(url: link.url) == link)
        #expect(PrimaryNavigationPolicy.opensHome(for: link) == false)
    }

    @Test("Widget project fallback URL uses todoshi scheme")
    func widgetFallbackURL() {
        #expect(TodoshiDeepLink.projects.url.absoluteString == "todoshi://projects")
    }

    @Test("Home toolbar project-management keys resolve in Arabic and English")
    func homeProjectManagementLocalization() {
        let en = Locale(identifier: "en")
        let ar = Locale(identifier: "ar")
        #expect(TodoshiL10n.tr("home.projectActions", locale: en) == "Project Actions")
        #expect(TodoshiL10n.tr("home.projectActions", locale: ar) == "إدارة المشاريع")
        #expect(TodoshiL10n.tr("project.new", locale: en) == "New Project")
        #expect(TodoshiL10n.tr("project.new", locale: ar) == "مشروع جديد")
        #expect(TodoshiL10n.tr("project.archivedTitle", locale: en) == "Archived Projects")
        #expect(TodoshiL10n.tr("project.archivedTitle", locale: ar) == "المشاريع المؤرشفة")
        #expect(TodoshiL10n.tr("dashboard.createProject", locale: en) == "Create Project")
        #expect(TodoshiL10n.tr("dashboard.createProject", locale: ar) == "إنشاء مشروع")
    }

    @Test("Dashboard deep link opens Home")
    func dashboardDeepLinkOpensHome() {
        let url = URL(string: "nexus://dashboard")!
        #expect(TodoshiDeepLink(url: url) == .dashboard)
        #expect(PrimaryNavigationPolicy.opensHome(for: .dashboard))
    }
}
