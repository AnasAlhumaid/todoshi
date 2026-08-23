import SwiftUI
import NexusCore

struct DayAgendaView: View {
    let agenda: CalendarDayAgenda
    let selectedDay: Date
    var onComplete: (UUID) -> Void
    var onReopen: (UUID) -> Void
    var onChangeDueDate: (UUID) -> Void
    var onRemoveDueDate: (UUID) -> Void
    var onAddTask: () -> Void

    var body: some View {
        if agenda.isEmpty {
            CalendarEmptyState(
                systemImage: "calendar.badge.exclamationmark",
                title: CalendarStrings.noTasksThisDay,
                message: NexusL10n.tr("calendar.dayEmptyMessage"),
                actionTitle: CalendarStrings.addTask,
                action: onAddTask
            )
        } else {
            if !agenda.overdueWhenToday.isEmpty {
                Section {
                    ForEach(agenda.overdueWhenToday) { task in
                        taskLink(task)
                    }
                } header: {
                    Text(CalendarStrings.overdue)
                }
            }

            Section {
                ForEach(agenda.dueOnDay) { task in
                    taskLink(task)
                }
            } header: {
                Text(selectedDay, format: .dateTime.weekday(.wide).month(.wide).day().year())
            }
        }
    }

    @ViewBuilder
    private func taskLink(_ task: CalendarTaskItem) -> some View {
        NavigationLink(value: AppRoute.task(task.id)) {
            CalendarTaskRowView(task: task)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if task.status == .done {
                Button(CalendarStrings.markIncomplete) { onReopen(task.id) }
                    .tint(.orange)
            } else {
                Button(CalendarStrings.markDone) { onComplete(task.id) }
                    .tint(.green)
            }
        }
        .contextMenu {
            if task.status == .done {
                Button(CalendarStrings.markIncomplete) { onReopen(task.id) }
            } else {
                Button(CalendarStrings.markDone) { onComplete(task.id) }
            }
            Button(CalendarStrings.changeDueDate) { onChangeDueDate(task.id) }
            Button(CalendarStrings.removeDueDate, role: .destructive) { onRemoveDueDate(task.id) }
        }
    }
}
