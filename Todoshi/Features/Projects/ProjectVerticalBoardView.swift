import SwiftUI
import NexusCore

struct ProjectVerticalBoardView: View {
    let snapshot: ProjectBoardSnapshot
    let onAddTask: (TaskStatus) -> Void
    let onEditTask: (UUID) -> Void
    let onDeleteTask: (UUID) -> Void
    let onMoveToStatus: (UUID, TaskStatus) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAllDone = false

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 148, maximum: 220), spacing: NexusSpacing.sm, alignment: .top)]
    }

    private var boardAnimationKey: String {
        snapshot.sections
            .map { section in
                "\(section.status.rawValue):" + section.tasks.map(\.id.uuidString).joined(separator: ",")
            }
            .joined(separator: "|")
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: NexusSpacing.lg) {
                ForEach(snapshot.sections) { section in
                    statusSection(section)
                }
            }
            .padding(.horizontal, NexusSpacing.md)
            .padding(.vertical, NexusSpacing.sm)
            .animation(reduceMotion ? nil : .default, value: boardAnimationKey)
        }
    }

    @ViewBuilder
    private func statusSection(_ section: ProjectBoardSection) -> some View {
        VStack(alignment: .leading, spacing: NexusSpacing.sm) {
            sectionHeader(section)

            if section.tasks.isEmpty {
                emptySection(section.status)
            } else {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: NexusSpacing.sm) {
                    ForEach(visibleTasks(in: section)) { task in
                        ProjectBoardTaskCardView(
                            task: task,
                            sectionStatus: section.status,
                            onEdit: { onEditTask(task.id) },
                            onDelete: { onDeleteTask(task.id) },
                            onMoveToStatus: { onMoveToStatus(task.id, $0) }
                        )
                    }
                }

                if shouldShowDoneExpand(for: section) {
                    Button(NexusL10n.tr("common.showAll")) {
                        showsAllDone = true
                    }
                    .font(.subheadline)
                    .padding(.top, NexusSpacing.xxs)
                }
            }
        }
    }

    private func sectionHeader(_ section: ProjectBoardSection) -> some View {
        HStack(spacing: NexusSpacing.xs) {
            Circle()
                .fill(NexusStatusColor.indicator(for: section.status))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Text(section.status.displayName)
                .font(NexusTypography.section)

            Text("\(section.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: NexusSpacing.xs)

            Button {
                onAddTask(section.status)
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: NexusIconSize.hit, height: NexusIconSize.hit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NexusL10n.format("a11y.addTaskTo", section.status.displayName))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(NexusL10n.format("kanban.statusCount", section.status.displayName, section.count))
    }

    private func emptySection(_ status: TaskStatus) -> some View {
        VStack(alignment: .leading, spacing: NexusSpacing.xs) {
            Text(NexusL10n.tr("project.noTasks"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(NexusL10n.tr("calendar.addTask")) {
                onAddTask(status)
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, NexusSpacing.xxs)
    }

    private func visibleTasks(in section: ProjectBoardSection) -> [HomeTaskSummary] {
        guard section.status == .done else { return section.tasks }
        if showsAllDone || section.tasks.count <= ProjectBoardSnapshot.donePreviewLimit {
            return section.tasks
        }
        return Array(section.tasks.prefix(ProjectBoardSnapshot.donePreviewLimit))
    }

    private func shouldShowDoneExpand(for section: ProjectBoardSection) -> Bool {
        section.status == .done
            && !showsAllDone
            && section.tasks.count > ProjectBoardSnapshot.donePreviewLimit
    }
}
