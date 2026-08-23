import Foundation
import Observation
import SwiftData
import NexusCore

@Observable
@MainActor
final class SearchViewModel {
    var query: String = ""
    var includeArchived: Bool = false
    private(set) var recentTerms: [String] = []
    private(set) var snapshot = SearchSnapshot()

    private let locale: Locale
    var projectPreviewLimit: Int
    var taskPreviewLimit: Int

    init(
        includeArchived: Bool = false,
        locale: Locale = .current,
        projectPreviewLimit: Int = SearchBuilder.defaultProjectPreviewLimit,
        taskPreviewLimit: Int = SearchBuilder.defaultTaskPreviewLimit
    ) {
        self.includeArchived = includeArchived
        self.locale = locale
        self.projectPreviewLimit = projectPreviewLimit
        self.taskPreviewLimit = taskPreviewLimit
        self.recentTerms = RecentSearchesStore.load()
    }

    func rebuild(projects: [Project]) {
        snapshot = SearchMapping.snapshot(
            projects: projects,
            query: query,
            includeArchived: includeArchived,
            locale: locale,
            projectPreviewLimit: projectPreviewLimit,
            taskPreviewLimit: taskPreviewLimit
        )
    }

    var showsResults: Bool {
        !SearchText.isEmptyQuery(query)
    }

    var hasNoMatches: Bool {
        showsResults && !snapshot.hasResults
    }

    func recordCurrentQuery() {
        recentTerms = RecentSearchesStore.recording(query, into: recentTerms)
        RecentSearchesStore.save(recentTerms)
    }

    func applyRecent(_ term: String) {
        query = term
    }

    func deleteRecent(_ term: String) {
        recentTerms = RecentSearchesStore.deleting(term, from: recentTerms)
        RecentSearchesStore.save(recentTerms)
    }

    func clearRecents() {
        recentTerms = RecentSearchesStore.clearing()
        RecentSearchesStore.save(recentTerms)
    }

    func selectProjectResult(_ id: UUID) -> AppRoute {
        recordCurrentQuery()
        return .project(id)
    }

    func selectTaskResult(_ id: UUID) -> AppRoute {
        recordCurrentQuery()
        return .task(id)
    }
}
