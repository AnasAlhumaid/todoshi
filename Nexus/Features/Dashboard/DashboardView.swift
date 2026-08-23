import SwiftUI
import SwiftData
import NexusCore

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Query private var projects: [Project]

    @State private var isCreatingProject = false
    @State private var creatingTaskProjectID: UUID?
    @State private var actionError: String?

    private var summaries: [HomeProjectSummary] {
        HomeMapping.projectSummaries(from: projects)
    }

    var body: some View {
        Group {
            if summaries.isEmpty {
                emptyNoProjects
            } else {
                projectOverview
            }
        }
        .navigationTitle(NexusL10n.tr("dashboard.title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button(NexusL10n.tr("project.new")) {
                        isCreatingProject = true
                    }
                    NavigationLink(value: AppRoute.archivedProjects) {
                        Text(NexusL10n.tr("project.archivedTitle"))
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(NexusL10n.tr("home.projectActions"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.presentQuickAdd()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(NexusL10n.tr("dashboard.quickAdd"))
            }
        }
        .sheet(isPresented: $isCreatingProject) {
            NavigationStack {
                ProjectFormView(context: modelContext)
            }
        }
        .sheet(isPresented: Binding(
            get: { creatingTaskProjectID != nil },
            set: { if !$0 { creatingTaskProjectID = nil } }
        )) {
            NavigationStack {
                if let creatingTaskProjectID {
                    TaskFormView(
                        context: modelContext,
                        projectID: creatingTaskProjectID,
                        taskID: nil,
                        initialStatus: .todo
                    )
                }
            }
        }
        .alert(
            NexusL10n.tr("common.somethingWrong"),
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button(NexusL10n.tr("common.ok"), role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var projectOverview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: NexusSpacing.md) {
                Text(NexusL10n.tr("home.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, NexusSpacing.xxs)

                ForEach(summaries) { project in
                    HomeProjectNoteCardView(
                        project: project,
                        onAddTask: { creatingTaskProjectID = project.id },
                        onMoveTaskStatus: { taskID, status in
                            _ = commitMove(taskID: taskID, to: status)
                        }
                    )
                }
            }
            .padding(.horizontal, NexusSpacing.md)
            .padding(.vertical, NexusSpacing.sm)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var emptyNoProjects: some View {
        ContentUnavailableView {
            Label(NexusL10n.tr("home.noProjects"), systemImage: "folder.badge.plus")
        } description: {
            Text(NexusL10n.tr("home.noProjectsMessage"))
        } actions: {
            Button(NexusL10n.tr("dashboard.createProject")) { isCreatingProject = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    @discardableResult
    private func commitMove(taskID: UUID, to status: TaskStatus) -> Bool {
        let repo = TaskRepository(context: modelContext)
        do {
            let previousStatus = try repo.fetchTask(id: taskID)?.status
            let didWrite = try repo.move(taskID: taskID, to: status, before: nil)
            if didWrite {
                NexusHaptics.taskStatusChanged(crossStatus: previousStatus != status)
            }
            return didWrite
        } catch {
            actionError = UserFacingError.message(for: error)
            return false
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .environment(AppRouter())
    .modelContainer(try! ModelContainerFactory.makeContainer(kind: .inMemory))
}
