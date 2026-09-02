import SwiftUI
import NexusCore

struct SearchProjectResultRow: View {
    let project: SearchableProject

    var body: some View {
        HStack(spacing: NexusSpacing.sm) {
            Image(systemName: project.icon)
                .font(.body)
                .foregroundStyle(NexusColor.from(hex: project.colorHex))
                .frame(width: NexusIconSize.glyph, height: NexusIconSize.glyph)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: NexusSpacing.xs) {
                    Text(project.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if project.isArchived {
                        Text(NexusL10n.tr("common.archived"))
                            .font(NexusTypography.metadata)
                            .foregroundStyle(.secondary)
                    }
                }
                if !project.projectDescription.isEmpty {
                    Text(project.projectDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Text("\(project.openRootCount)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel(NexusL10n.format("search.openTasksA11y", project.openRootCount))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [project.name]
        if project.isArchived { parts.append(NexusL10n.tr("common.archived")) }
        if !project.projectDescription.isEmpty { parts.append(project.projectDescription) }
        parts.append("\(project.openRootCount) open tasks")
        return parts.joined(separator: ", ")
    }
}

struct SearchTaskResultRow: View {
    let task: SearchableTask

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
            isOverdue: TaskPredicates.isOverdue(task.dueDate, status: task.status),
            showStatus: true,
            labels: task.labels.prefix(2).map { (id: $0.id, name: $0.name, colorHex: $0.colorHex) }
        )
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [task.title, task.projectName, task.status.displayName]
        if task.priority != .none {
            parts.append(NexusL10n.format("search.priorityA11y", task.priority.displayName))
        }
        if task.projectIsArchived {
            parts.append(NexusL10n.tr("search.archivedProject"))
        }
        if TaskPredicates.isOverdue(task.dueDate, status: task.status) {
            parts.append(NexusL10n.tr("common.overdue"))
        }
        if !task.labelNames.isEmpty {
            parts.append(task.labelNames.joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }
}
