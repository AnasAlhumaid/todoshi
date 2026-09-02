import SwiftUI
import NexusCore

struct DashboardTaskRowView: View {
    let task: DashboardTaskInput
    var overdueEmphasis: Bool = false

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
            isOverdue: overdueEmphasis || TaskPredicates.isOverdue(task.dueDate, status: task.status),
            showsLabels: false
        )
    }
}
