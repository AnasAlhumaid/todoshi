import SwiftUI
import TodoshiCore

struct HomeProjectNoteCardView: View {
    let project: HomeProjectSummary
    let onAddTask: () -> Void
    var onMoveTaskStatus: ((UUID, TaskStatus) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: TodoshiSpacing.xs) {
            header
            cardBody
        }
        .padding(TodoshiSpacing.md)
        .background(
            TodoshiBrand.projectWash(for: project.colorHex),
            in: RoundedRectangle(cornerRadius: TodoshiRadius.card, style: .continuous)
        )
        .todoshiSurface(cornerRadius: TodoshiRadius.card)
    }

    private var showsDescription: Bool {
        !project.projectDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var addActionLabel: String {
        project.projectType == .checklist
            ? ProjectTerminologyPolicy.addItem(.checklist)
            : TodoshiL10n.tr("calendar.addTask")
    }

    @ViewBuilder
    private var cardBody: some View {
        if showsDescription {
            projectNavigationLink {
                Text(project.projectDescription)
                    .font(TodoshiTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }

        if project.tasks.isEmpty {
            Text(
                project.projectType == .checklist
                    ? ProjectTerminologyPolicy.emptyTitle(.checklist)
                    : TodoshiL10n.tr("widget.noOpenTasks")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                            .opacity(0.5)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: TodoshiSpacing.xs) {
            projectNavigationLink {
                HStack(alignment: .center, spacing: TodoshiSpacing.xs) {
                    TodoshiProjectIconWell(
                        systemName: project.icon,
                        colorHex: project.colorHex,
                        projectType: project.projectType
                    )

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: TodoshiSpacing.xxs) {
                            Text(project.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            if project.isShared {
                                Image(systemName: SharedProjectPresentation.indicatorSystemImage)
                                    .font(.caption2)
                                    .foregroundStyle(TodoshiBrand.accent.opacity(0.7))
                                    .accessibilityLabel(SharedProjectPresentation.accessibilityLabel())
                            }
                        }
                        Text(openCountLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }

            TodoshiCompactAddAction(label: addActionLabel, action: onAddTask)
        }
        .accessibilityElement(children: .contain)
    }

    private var openCountLabel: String {
        project.projectType == .checklist
            ? ProjectTerminologyPolicy.openItemsCount(project.openTaskCount)
            : TodoshiL10n.plural("widget.openTasksCount", count: project.openTaskCount)
    }

    private func projectNavigationLink<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationLink(value: AppRoute.project(project.id)) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(project.name)
        .accessibilityHint(TodoshiL10n.tr("kanban.opensDetails"))
    }
}
