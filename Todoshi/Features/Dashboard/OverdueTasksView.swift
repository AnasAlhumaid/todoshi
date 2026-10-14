import SwiftUI
import SwiftData
import TodoshiCore
import UIKit

struct OverdueTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var projects: [Project]

    @State private var actionError: String?

    private var overdueTasks: [DashboardTaskInput] {
        let allTasks = projects.flatMap { $0.tasks ?? [] }.compactMap(DashboardMapping.taskInput(from:))
        return DashboardBuilder.build(
            projects: projects.map(DashboardMapping.projectInput(from:)),
            tasks: allTasks,
            overduePreviewLimit: Int.max
        ).overdue
    }

    var body: some View {
        Group {
            if overdueTasks.isEmpty {
                ContentUnavailableView(
                    TodoshiL10n.tr("dashboard.noOverdue"),
                    systemImage: "checkmark.seal",
                    description: Text(TodoshiL10n.tr("overdue.empty"))
                )
            } else {
                List {
                    ForEach(overdueTasks) { task in
                        NavigationLink(value: AppRoute.task(task.id)) {
                            DashboardTaskRowView(task: task, overdueEmphasis: true)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(TodoshiL10n.tr("common.done")) {
                                complete(taskID: task.id)
                            }
                            .tint(.green)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(TodoshiL10n.tr("overdue.title"))
        .alert(
            TodoshiL10n.tr("common.somethingWrong"),
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button(TodoshiL10n.tr("common.ok"), role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private func complete(taskID: UUID) {
        do {
            guard let task = try TaskRepository(context: modelContext).fetchTask(id: taskID) else { return }
            try TaskRepository(context: modelContext).complete(task)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }
}
