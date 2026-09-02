import SwiftUI
import SwiftData
import NexusCore

struct ArchivedProjectsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var projects: [Project]

    @State private var projectPendingDelete: Project?
    @State private var restoreError: String?

    init() {
        let archived = ProjectStatus.archived.rawValue
        _projects = Query(
            filter: #Predicate<Project> { $0.statusRaw == archived },
            sort: [
                SortDescriptor(\Project.position),
                SortDescriptor(\Project.createdAt)
            ]
        )
    }

    var body: some View {
        Group {
            if projects.isEmpty {
                ContentUnavailableView(
                    NexusL10n.tr("project.noArchivedTitle"),
                    systemImage: "archivebox",
                    description: Text(NexusL10n.tr("project.archivedEmpty"))
                )
            } else {
                List {
                    ForEach(projects, id: \.id) { project in
                        ArchivedProjectRow(
                            project: project,
                            onRestore: { restore(project) },
                            onDelete: { projectPendingDelete = project }
                        )
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(NexusL10n.tr("project.archivedTitle"))
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: deleteDialogPresented,
            titleVisibility: .visible,
            presenting: projectPendingDelete
        ) { project in
            Button(NexusL10n.tr("common.delete"), role: .destructive) {
                delete(project)
            }
            Button(NexusL10n.tr("common.cancel"), role: .cancel) {}
        } message: { project in
            Text(Self.deleteMessage(for: project))
        }
    }

    private var deleteDialogTitle: String { "Delete Project?" }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(
            get: { projectPendingDelete != nil },
            set: { if !$0 { projectPendingDelete = nil } }
        )
    }

    private static func deleteMessage(for project: Project) -> String {
        let count = (project.tasks ?? []).count
        let unit = count == 1 ? "task" : "tasks"
        return "\"\(project.name)\" and \(count) \(unit) will be permanently deleted."
    }

    private func restore(_ project: Project) {
        do {
            try ProjectRepository(context: modelContext).restore(project)
        } catch {
            restoreError = UserFacingError.message(for: error)
        }
    }

    private func delete(_ project: Project) {
        do {
            try ProjectRepository(context: modelContext).delete(project)
            projectPendingDelete = nil
        } catch {
            restoreError = UserFacingError.message(for: error)
        }
    }
}

private struct ArchivedProjectRow: View {
    let project: Project
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationLink(value: AppRoute.project(project.id)) {
            ProjectRowView(
                project: project,
                openTaskCount: ProjectTaskCounts.openRootCount(tasks: project.tasks ?? [])
            )
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(NexusL10n.tr("project.restoreShort"), action: onRestore)
                .tint(.blue)
            Button(NexusL10n.tr("common.delete"), role: .destructive, action: onDelete)
        }
        .contextMenu {
            Button(NexusL10n.tr("project.restoreShort"), action: onRestore)
            Button(NexusL10n.tr("common.delete"), role: .destructive, action: onDelete)
        }
    }
}
