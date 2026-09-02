import SwiftUI
import SwiftData
import NexusCore
import UIKit

struct KanbanBoardView: View {
    let project: Project
    let rootTasks: [TaskItem]
    let dragState: KanbanDragState
    let onAddTask: (TaskStatus) -> Void
    let onEditTask: (TaskItem) -> Void
    let onDeleteTask: (TaskItem) -> Void
    let onCommitDrop: (UUID, TaskStatus, UUID?) -> Bool
    let onMoveToStatus: (TaskItem, TaskStatus) -> Void
    let onMoveEarlier: (TaskItem) -> Void
    let onMoveLater: (TaskItem) -> Void

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 320)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: NexusSpacing.sm) {
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        KanbanColumnView(
                            status: status,
                            tasks: tasks(for: status),
                            columnHeight: height - NexusSpacing.md,
                            dragState: dragState,
                            onAddTask: { onAddTask(status) },
                            onEditTask: onEditTask,
                            onDeleteTask: onDeleteTask,
                            onMoveToStatus: onMoveToStatus,
                            onMoveEarlier: onMoveEarlier,
                            onMoveLater: onMoveLater,
                            onCommitDrop: onCommitDrop
                        )
                    }
                }
                .padding(.horizontal, NexusSpacing.md)
                .padding(.vertical, NexusSpacing.xs)
            }
        }
    }

    private func tasks(for status: TaskStatus) -> [TaskItem] {
        rootTasks
            .filter { $0.status == status }
            .sorted {
                if $0.position != $1.position { return $0.position < $1.position }
                return $0.createdAt < $1.createdAt
            }
    }
}

enum KanbanHaptics {
    static func moveCommitted(crossColumn: Bool) {
        let style: UIImpactFeedbackGenerator.FeedbackStyle = crossColumn ? .medium : .light
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
