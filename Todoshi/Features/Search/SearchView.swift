import SwiftUI
import SwiftData
import NexusCore

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var projects: [Project]

    @AppStorage(SearchPreferences.includeArchivedKey) private var includeArchived = false
    @State private var viewModel = SearchViewModel()
    @State private var isCreatingProject = false
    @State private var path = NavigationPath()

    /// Bound so query survives navigation and rebuilds when projects change.
    private var dataRevision: String {
        projects
            .map { project in
                let taskStamp = (project.tasks ?? [])
                    .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" }
                    .joined(separator: ",")
                return "\(project.id.uuidString):\(project.position):\(project.updatedAt.timeIntervalSince1970):\(taskStamp)"
            }
            .joined(separator: "|")
    }

    private var activeProjectsCount: Int {
        projects.filter { $0.status == .active }.count
    }

    var body: some View {
        List {
            if projects.isEmpty {
                noDataSection
            } else if !viewModel.showsResults {
                idleSections
            } else if viewModel.hasNoMatches {
                noMatchesSection
            } else {
                resultsSections
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NexusL10n.tr("search.navTitle"))
        .searchable(
            text: $viewModel.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(SearchStrings.prompt)
        )
        .onSubmit(of: .search) {
            viewModel.recordCurrentQuery()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $includeArchived) {
                    Image(systemName: includeArchived ? "archivebox.fill" : "archivebox")
                }
                .toggleStyle(.button)
                .accessibilityLabel(includeArchived ? NexusL10n.tr("search.includingArchivedA11y") : NexusL10n.tr("search.includeArchivedA11y"))
                .accessibilityHint(NexusL10n.tr("search.includeArchivedHint"))
            }
        }
        .onChange(of: viewModel.query) { _, _ in
            rebuildResults()
        }
        .onChange(of: includeArchived) { _, _ in
            rebuildResults()
        }
        .onChange(of: dataRevision) { _, _ in
            rebuildResults()
        }
        .onAppear {
            rebuildResults()
        }
        .sheet(isPresented: $isCreatingProject) {
            NavigationStack {
                ProjectFormView(context: modelContext)
            }
        }
    }

    private func rebuildResults() {
        viewModel.includeArchived = includeArchived
        viewModel.rebuild(projects: projects)
    }

    // MARK: - Sections

    private var noDataSection: some View {
        Section {
            ContentUnavailableView {
                Label(SearchStrings.noProjectsTitle, systemImage: "folder.badge.plus")
            } description: {
                Text(SearchStrings.noProjectsMessage)
            } actions: {
                Button(SearchStrings.createProject) {
                    isCreatingProject = true
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var idleSections: some View {
        if !viewModel.recentTerms.isEmpty {
            Section {
                ForEach(viewModel.recentTerms, id: \.self) { term in
                    HStack {
                        Button {
                            viewModel.applyRecent(term)
                            viewModel.rebuild(projects: projects)
                        } label: {
                            Label(term, systemImage: "clock.arrow.circlepath")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(NexusL10n.format("search.forTermA11y", term))

                        Button(role: .destructive) {
                            viewModel.deleteRecent(term)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(NexusL10n.format("search.removeRecentA11y", term))
                    }
                }

                Button(SearchStrings.clearRecents, role: .destructive) {
                    viewModel.clearRecents()
                }
            } header: {
                Text(SearchStrings.recentTitle)
            }
        }

        if activeProjectsCount > 0 {
            Section {
                ForEach(quickLinkProjects, id: \.id) { project in
                    NavigationLink(value: AppRoute.project(project.id)) {
                        SearchProjectResultRow(project: SearchMapping.project(project))
                    }
                }
            } header: {
                Text(SearchStrings.quickLinksTitle)
            }
        }
    }

    private var quickLinkProjects: [Project] {
        projects
            .filter { $0.status == .active }
            .sorted {
                if $0.position != $1.position { return $0.position < $1.position }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .prefix(5)
            .map { $0 }
    }

    private var noMatchesSection: some View {
        Section {
            ContentUnavailableView {
                Label(SearchStrings.noResultsTitle, systemImage: "magnifyingglass")
            } description: {
                Text(SearchStrings.noResultsMessage(for: viewModel.snapshot.query))
            } actions: {
                Button(SearchStrings.clearSearch) {
                    viewModel.query = ""
                    viewModel.rebuild(projects: projects)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var resultsSections: some View {
        if !viewModel.snapshot.projects.isEmpty {
            Section {
                ForEach(viewModel.snapshot.projects) { item in
                    NavigationLink(value: AppRoute.project(item.id)) {
                        SearchProjectResultRow(project: item.project)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        viewModel.recordCurrentQuery()
                    })
                }
            } header: {
                Text(SearchStrings.projectsHeader(count: viewModel.snapshot.projectTotalCount))
            } footer: {
                if viewModel.snapshot.projectTotalCount > viewModel.snapshot.projects.count {
                    Text(SearchStrings.showingPreview(
                        visible: viewModel.snapshot.projects.count,
                        total: viewModel.snapshot.projectTotalCount
                    ))
                    .font(.caption)
                }
            }
        }

        if !viewModel.snapshot.tasks.isEmpty {
            Section {
                ForEach(viewModel.snapshot.tasks) { item in
                    NavigationLink(value: AppRoute.task(item.id)) {
                        SearchTaskResultRow(task: item.task)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        viewModel.recordCurrentQuery()
                    })
                }
            } header: {
                Text(SearchStrings.tasksHeader(count: viewModel.snapshot.taskTotalCount))
            } footer: {
                if viewModel.snapshot.taskTotalCount > viewModel.snapshot.tasks.count {
                    Text(SearchStrings.showingPreview(
                        visible: viewModel.snapshot.tasks.count,
                        total: viewModel.snapshot.taskTotalCount
                    ))
                    .font(.caption)
                }
            }
        }
    }
}

/// Centralized user-facing search copy.
enum SearchStrings {
    static var prompt: String { NexusL10n.tr("search.prompt") }
    static var recentTitle: String { NexusL10n.tr("search.recent") }
    static var quickLinksTitle: String { NexusL10n.tr("search.activeProjects") }
    static var clearRecents: String { NexusL10n.tr("search.clearRecent") }
    static var clearSearch: String { NexusL10n.tr("search.clear") }
    static var noProjectsTitle: String { NexusL10n.tr("search.noProjectsTitle") }
    static var noProjectsMessage: String { NexusL10n.tr("search.noProjectsMessage") }
    static var createProject: String { NexusL10n.tr("search.createProject") }
    static var noResultsTitle: String { NexusL10n.tr("search.noResults") }

    static func noResultsMessage(for query: String) -> String {
        NexusL10n.format("search.noResultsMessage", query)
    }

    static func projectsHeader(count: Int) -> String {
        NexusL10n.format("search.projectsHeader", count)
    }

    static func tasksHeader(count: Int) -> String {
        NexusL10n.format("search.tasksHeader", count)
    }

    static func showingPreview(visible: Int, total: Int) -> String {
        NexusL10n.format("search.showingPreview", visible, total)
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
    .modelContainer(try! ModelContainerFactory.makeContainer(kind: .inMemory))
}
