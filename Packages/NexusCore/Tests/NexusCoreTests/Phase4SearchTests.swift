import Foundation
import Testing
@testable import NexusCore

struct Phase4SearchTests {
    private let locale = Locale(identifier: "en_US_POSIX")

    // MARK: Normalization

    @Test("Query normalization trims and collapses whitespace")
    func normalizeQuery() {
        #expect(SearchText.normalizeQuery("  hello   world  ") == "hello world")
        #expect(SearchText.normalizeQuery("\n\t") == "")
        #expect(SearchText.isEmptyQuery("   "))
        #expect(SearchText.isEmptyQuery("x") == false)
    }

    @Test("Case and diacritic insensitive matching")
    func caseDiacritic() {
        #expect(SearchText.matches("Café", query: "cafe", locale: locale))
        #expect(SearchText.matches("HELLO", query: "hello", locale: locale))
        #expect(SearchText.isExactMatch("Nexus", query: "nexus", locale: locale))
        #expect(SearchText.isPrefixMatch("Nexus Core", query: "nex", locale: locale))
        #expect(SearchText.isPrefixMatch("Core Nexus", query: "nex", locale: locale) == false)
    }

    @Test("Arabic text matching")
    func arabicMatching() {
        let ar = Locale(identifier: "ar")
        #expect(SearchText.matches("مشروع نكسس", query: "نكسس", locale: ar))
        #expect(SearchText.isPrefixMatch("مشروع", query: "مش", locale: ar))
        #expect(SearchText.matches("Task عنوان", query: "عنوان", locale: ar))
    }

    // MARK: Project ranking

    @Test("Project ranking exact > prefix > contains > description")
    func projectRanking() {
        let exact = SearchRelevance.projectScore(name: "Alpha", description: "", query: "alpha", locale: locale)
        let prefix = SearchRelevance.projectScore(name: "Alphabet", description: "", query: "alpha", locale: locale)
        let contains = SearchRelevance.projectScore(name: "The Alpha App", description: "", query: "alpha", locale: locale)
        let desc = SearchRelevance.projectScore(name: "Other", description: "alpha related", query: "alpha", locale: locale)
        #expect(exact > prefix)
        #expect(prefix > contains)
        #expect(contains > desc)
        #expect(desc > 0)
    }

    @Test("Project search respects archived flag and position ties")
    func projectSearchArchiveAndTie() {
        let a = SearchableProject(id: UUID(), name: "Zed", position: 2000)
        let b = SearchableProject(id: UUID(), name: "Zed", position: 1000)
        let archived = SearchableProject(id: UUID(), name: "Zed", position: 1, isArchived: true)

        let activeOnly = SearchBuilder.build(
            query: "zed",
            projects: [a, b, archived],
            tasks: [],
            includeArchived: false,
            locale: locale
        )
        #expect(activeOnly.projectTotalCount == 2)
        #expect(activeOnly.projects.map(\.project.position) == [1000, 2000])

        let withArchived = SearchBuilder.build(
            query: "zed",
            projects: [a, b, archived],
            tasks: [],
            includeArchived: true,
            locale: locale
        )
        #expect(withArchived.projectTotalCount == 3)
        #expect(withArchived.projects.contains { $0.project.isArchived })
    }

    // MARK: Task ranking

    @Test("Task ranking title > project > label > description > notes")
    func taskRanking() {
        let projectID = UUID()
        let titleExact = SearchRelevance.taskScore(
            title: "Nexus", projectName: "P", description: "", notes: "", labelNames: [], query: "nexus", locale: locale
        )
        let titlePrefix = SearchRelevance.taskScore(
            title: "Nexus board", projectName: "P", description: "", notes: "", labelNames: [], query: "nexus", locale: locale
        )
        let projectMatch = SearchRelevance.taskScore(
            title: "Other", projectName: "Nexus", description: "", notes: "", labelNames: [], query: "nexus", locale: locale
        )
        let labelMatch = SearchRelevance.taskScore(
            title: "Other", projectName: "P", description: "", notes: "", labelNames: ["nexus"], query: "nexus", locale: locale
        )
        let desc = SearchRelevance.taskScore(
            title: "Other", projectName: "P", description: "about nexus", notes: "", labelNames: [], query: "nexus", locale: locale
        )
        let notes = SearchRelevance.taskScore(
            title: "Other", projectName: "P", description: "", notes: "nexus note", labelNames: [], query: "nexus", locale: locale
        )
        #expect(titleExact > titlePrefix)
        #expect(titlePrefix > projectMatch)
        #expect(projectMatch > labelMatch)
        #expect(labelMatch > desc)
        #expect(desc > notes)
        _ = projectID
    }

    @Test("Task search root-only, fields, archive exclusion, updatedAt ties")
    func taskSearchRules() {
        let active = UUID()
        let archived = UUID()
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        let tasks = [
            SearchableTask(
                title: "Fix bug",
                taskDescription: "detail",
                notes: "remember",
                updatedAt: older,
                projectID: active,
                projectName: "App",
                labelNames: ["ios"]
            ),
            SearchableTask(
                title: "Sibling",
                updatedAt: newer,
                isRoot: false,
                projectID: active,
                projectName: "App"
            ),
            SearchableTask(
                title: "Archived task",
                projectID: archived,
                projectName: "Old",
                projectIsArchived: true
            ),
            SearchableTask(
                title: "Other",
                taskDescription: "Fix bug wording",
                updatedAt: newer,
                projectID: active,
                projectName: "App"
            )
        ]

        let byTitle = SearchBuilder.build(
            query: "Fix bug",
            projects: [],
            tasks: tasks,
            includeArchived: false,
            locale: locale
        )
        #expect(byTitle.taskTotalCount == 2)
        #expect(byTitle.tasks.first?.task.title == "Fix bug")

        let byNotes = SearchBuilder.build(
            query: "remember",
            projects: [],
            tasks: tasks,
            includeArchived: false,
            locale: locale
        )
        #expect(byNotes.tasks.map(\.task.title) == ["Fix bug"])

        let byLabel = SearchBuilder.build(
            query: "ios",
            projects: [],
            tasks: tasks,
            includeArchived: false,
            locale: locale
        )
        #expect(byLabel.tasks.map(\.task.title) == ["Fix bug"])

        let byProject = SearchBuilder.build(
            query: "App",
            projects: [],
            tasks: tasks,
            includeArchived: false,
            locale: locale
        )
        #expect(byProject.tasks.allSatisfy { !$0.task.projectIsArchived })
        #expect(byProject.tasks.allSatisfy { $0.task.isRoot })

        let noArchived = SearchBuilder.build(
            query: "Archived",
            projects: [],
            tasks: tasks,
            includeArchived: false,
            locale: locale
        )
        #expect(noArchived.taskTotalCount == 0)

        let withArchived = SearchBuilder.build(
            query: "Archived",
            projects: [],
            tasks: tasks,
            includeArchived: true,
            locale: locale
        )
        #expect(withArchived.taskTotalCount == 1)
    }

    @Test("Empty query yields no standard results; limits apply")
    func emptyQueryAndLimits() {
        let projects = (0..<8).map { i in
            SearchableProject(name: "Project \(i) Alpha", position: Double(i))
        }
        let empty = SearchBuilder.build(
            query: "  ",
            projects: projects,
            tasks: [],
            includeArchived: false,
            locale: locale
        )
        #expect(empty.isEmptyQuery)
        #expect(empty.projects.isEmpty)
        #expect(empty.tasks.isEmpty)

        let limited = SearchBuilder.build(
            query: "Alpha",
            projects: projects,
            tasks: [],
            includeArchived: false,
            locale: locale,
            projectPreviewLimit: 3
        )
        #expect(limited.projectTotalCount == 8)
        #expect(limited.projects.count == 3)
    }

    @Test("No duplicate tasks when multiple fields match")
    func noDuplicateTasks() {
        let task = SearchableTask(
            title: "Nexus",
            taskDescription: "Nexus desc",
            notes: "Nexus notes",
            projectID: UUID(),
            projectName: "Nexus"
        )
        let snap = SearchBuilder.build(
            query: "Nexus",
            projects: [],
            tasks: [task],
            includeArchived: false,
            locale: locale
        )
        #expect(snap.taskTotalCount == 1)
        #expect(snap.tasks.count == 1)
    }

    // MARK: Recent searches

    @Test("Recent searches record, dedupe, cap, delete, clear")
    func recentSearches() {
        var store: [String] = []
        store = RecentSearchesStore.recording("  Alpha  ", into: store)
        store = RecentSearchesStore.recording("beta", into: store)
        store = RecentSearchesStore.recording("ALPHA", into: store)
        #expect(store.first == "ALPHA" || store.first?.caseInsensitiveCompare("alpha") == .orderedSame)
        #expect(store.filter { $0.caseInsensitiveCompare("alpha") == .orderedSame }.count == 1)

        for i in 0..<10 {
            store = RecentSearchesStore.recording("term\(i)", into: store)
        }
        #expect(store.count == RecentSearchesStore.maxTerms)

        store = RecentSearchesStore.deleting("term9", from: store)
        #expect(store.contains("term9") == false)

        store = RecentSearchesStore.recording("   ", into: store)
        #expect(!store.contains(where: { $0.isEmpty }))

        store = RecentSearchesStore.clearing()
        #expect(store.isEmpty)
    }

    @Test("Search navigation destinations")
    func navigationHelpers() {
        let pid = UUID()
        let tid = UUID()
        #expect(SearchNavigation.route(forProjectID: pid) == .project(pid))
        #expect(SearchNavigation.route(forTaskID: tid) == .task(tid))
    }
}
