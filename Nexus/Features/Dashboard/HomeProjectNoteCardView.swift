import SwiftUI
import NexusCore

struct HomeProjectNoteCardView: View {
    let project: HomeProjectSummary
    let onAddTask: () -> Void
    var onMoveTaskStatus: ((UUID, TaskStatus) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: NexusSpacing.sm) {
            header

            if showsDescription {
                Text(project.projectDescription)
                    .font(NexusTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if project.tasks.isEmpty {
                emptyTasks
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(project.tasks.enumerated()), id: \.element.id) { index, task in
                        HomeTaskRowView(
                            task: task,
                            onMoveToStatus: onMoveTaskStatus.map { move in
                                { status in move(task.id, status) }
                            }
                        )
                        if index < project.tasks.count - 1 {
                            Divider()
                                .padding(.leading, NexusSpacing.sm + 3)
                        }
                    }
                }
            }
        }
        .padding(NexusSpacing.md)
        .background {
            RoundedRectangle(cornerRadius: NexusRadius.md, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(NexusColor.from(hex: project.colorHex).opacity(0.75))
                .frame(width: 3)
                .padding(.vertical, NexusSpacing.sm)
        }
    }

    private var showsDescription: Bool {
        !project.projectDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var header: some View {
        HStack(alignment: .center, spacing: NexusSpacing.sm) {
            NavigationLink(value: AppRoute.project(project.id)) {
                HStack(alignment: .center, spacing: NexusSpacing.sm) {
                    NexusProjectGlyph(systemName: project.icon, colorHex: project.colorHex, size: NexusIconSize.row)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(NexusL10n.plural("widget.openTasksCount", count: project.openTaskCount))
                            .font(NexusTypography.metadata)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onAddTask) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: NexusIconSize.hit, height: NexusIconSize.hit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NexusL10n.format("a11y.addTaskTo", project.name))
        }
        .accessibilityElement(children: .contain)
    }

    private var emptyTasks: some View {
        HStack(spacing: NexusSpacing.sm) {
            Text(NexusL10n.tr("widget.noOpenTasks"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: NexusSpacing.xs)
            Button(NexusL10n.tr("calendar.addTask"), action: onAddTask)
                .font(.subheadline)
        }
        .frame(minHeight: NexusIconSize.hit, alignment: .leading)
    }
}
