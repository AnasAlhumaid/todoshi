import SwiftUI
import SwiftData
import NexusCore
import UIKit

struct UpcomingTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var projects: [Project]
    @State private var actionError: String?

    private var groups: [UpcomingGroup] {
        CalendarScheduleBuilder.upcoming(
            tasks: CalendarMapping.taskSources(projects: projects),
            now: .now,
            calendar: .autoupdatingCurrent
        )
    }

    var body: some View {
        List {
            if groups.isEmpty {
                CalendarEmptyState(
                    systemImage: "clock",
                    title: CalendarStrings.noUpcoming,
                    message: NexusL10n.tr("calendar.upcomingEmptyMessage")
                )
            } else {
                ForEach(groups) { group in
                    Section(group.kind.title) {
                        ForEach(group.tasks) { task in
                            NavigationLink(value: AppRoute.task(task.id)) {
                                CalendarTaskRowView(task: task)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(CalendarStrings.markDone) {
                                    complete(taskID: task.id)
                                }
                                .tint(.green)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(CalendarStrings.upcoming)
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
