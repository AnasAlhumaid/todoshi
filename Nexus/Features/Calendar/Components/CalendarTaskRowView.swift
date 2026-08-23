import SwiftUI
import NexusCore

struct CalendarTaskRowView: View {
    let task: CalendarTaskItem
    var showTime: Bool = true

    var body: some View {
        NexusTaskRow(
            title: task.title,
            isCompleted: task.status == .done,
            context: task.projectName,
            projectIcon: task.projectIcon,
            projectColorHex: task.projectColorHex,
            priority: task.priority,
            dueDate: task.dueDate,
            status: task.status,
            isOverdue: task.isOverdue,
            showTime: showTime,
            isRecurring: task.isRecurring,
            checklist: task.checklistProgress,
            subtasks: task.subtaskProgress,
            showsLabels: false
        )
    }
}

struct CalendarUnscheduledRowView: View {
    let task: CalendarTaskSource

    var body: some View {
        NexusTaskRow(
            title: task.title,
            context: task.projectName,
            projectIcon: task.projectIcon,
            projectColorHex: task.projectColorHex,
            priority: task.priority,
            status: task.status,
            showStatus: true,
            showsLabels: false
        )
    }
}
