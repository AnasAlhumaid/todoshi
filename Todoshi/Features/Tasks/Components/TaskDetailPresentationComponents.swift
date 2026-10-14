import SwiftUI
import TodoshiCore

enum TaskDetailContentTab: String, CaseIterable, Identifiable {
    case details
    case comments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .details: TodoshiL10n.tr("task.detail.tab.details")
        case .comments: TaskCommentStrings.comments
        }
    }
}

// MARK: - Header

struct TaskDetailHeaderView: View {
    let projectName: String?
    let projectIcon: String?
    let projectColorHex: String?
    let projectType: ProjectType
    let title: String
    let status: TaskStatus
    let isSubtask: Bool
    var isStatusEditable: Bool = false
    var onStatusSelect: ((TaskStatus) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: TodoshiSpacing.sm) {
            if let projectName {
                HStack(spacing: TodoshiSpacing.xs) {
                    if let projectIcon, let projectColorHex {
                        TodoshiProjectIconWell(
                            systemName: projectIcon,
                            colorHex: projectColorHex,
                            size: 22,
                            projectType: projectType
                        )
                    }
                    Text(projectName)
                        .font(TodoshiTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: TodoshiSpacing.sm) {
                statusControl
                if isSubtask, !projectType.isChecklist {
                    Text(SubtaskStrings.subtask)
                        .font(TodoshiTypography.metadata)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var statusControl: some View {
        if isStatusEditable, let onStatusSelect {
            Menu {
                ForEach(ProjectTypeCapabilities.allowedStatuses(for: projectType), id: \.self) { candidate in
                    Button {
                        guard candidate != status else { return }
                        onStatusSelect(candidate)
                    } label: {
                        if candidate == status {
                            Label(
                                ProjectStatusPolicy.displayName(candidate, for: projectType),
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(ProjectStatusPolicy.displayName(candidate, for: projectType))
                        }
                    }
                }
            } label: {
                TodoshiStatusBadge(status: status, projectType: projectType)
            }
            .accessibilityLabel(
                TodoshiL10n.format("task.statusControl.a11y", status.displayName)
            )
            .accessibilityHint(TodoshiL10n.tr("task.statusControl.hint"))
        } else {
            TodoshiStatusBadge(status: status, projectType: projectType)
        }
    }
}

private extension ProjectType {
    var isChecklist: Bool { self == .checklist }
}

// MARK: - Metadata card

struct TaskDetailMetadataCard: View {
    let projectName: String?
    let projectIcon: String?
    let projectColorHex: String?
    let projectType: ProjectType
    let assigneeName: String?
    let showsAssignee: Bool
    let priority: TaskPriority
    let dueDate: Date?
    let taskStatus: TaskStatus
    let completionLine: String?

    var body: some View {
        VStack(spacing: 0) {
            if let projectName {
                TaskDetailMetadataRow(label: TodoshiL10n.tr("common.project")) {
                    HStack(spacing: TodoshiSpacing.xs) {
                        if let projectIcon, let projectColorHex {
                            TodoshiProjectGlyph(
                                systemName: projectIcon,
                                colorHex: projectColorHex,
                                size: 18
                            )
                        }
                        Text(projectName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
                rowDivider
            }

            if showsAssignee {
                TaskDetailMetadataRow(label: TaskAssignmentPresentation.assigneeLabel) {
                    HStack(spacing: TodoshiSpacing.xs) {
                        if assigneeName != TaskAssignmentPresentation.unassigned {
                            TodoshiAvatar(displayName: assigneeName, size: 28)
                        }
                        Text(assigneeName ?? TaskAssignmentPresentation.unassigned)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(
                                assigneeName == TaskAssignmentPresentation.unassigned
                                    ? .secondary : .primary
                            )
                            .lineLimit(1)
                    }
                }
                rowDivider
            }

            if priority != .none, !projectType.isChecklist {
                TaskDetailMetadataRow(label: TodoshiL10n.tr("common.priority")) {
                    HStack(spacing: 4) {
                        Image(systemName: prioritySymbol(priority))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(priorityTint(priority))
                        Text(priority.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(priorityTint(priority))
                    }
                }
                rowDivider
            }

            if let dueDate {
                TaskDetailMetadataRow(label: TodoshiL10n.tr("common.dueDate")) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundStyle(
                                TaskPredicates.isOverdue(dueDate, status: taskStatus) ? .red : .secondary
                            )
                        Text(dueDate, style: .date)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(
                                TaskPredicates.isOverdue(dueDate, status: taskStatus) ? .red : .primary
                            )
                    }
                }
                rowDivider
            }

            if let completionLine {
                TaskDetailMetadataRow(label: TaskCompletionPresentation.completedByLabel) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(TodoshiStatusColor.indicator(for: .done))
                        Text(completionLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .padding(.vertical, TodoshiSpacing.xxs)
        .todoshiSurface(cornerRadius: TodoshiRadius.card)
    }

    @ViewBuilder
    private var rowDivider: some View {
        Divider()
            .padding(.leading, TodoshiSpacing.md)
    }

    private func prioritySymbol(_ priority: TaskPriority) -> String {
        switch priority {
        case .none: return "minus"
        case .low: return "arrow.down"
        case .medium: return "equal"
        case .high: return "arrow.up"
        case .urgent: return "exclamationmark"
        }
    }

    private func priorityTint(_ priority: TaskPriority) -> Color {
        switch priority {
        case .none: return .secondary
        case .low: return .secondary
        case .medium: return .orange
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

struct TaskDetailMetadataRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack(alignment: .center, spacing: TodoshiSpacing.md) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            value()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, TodoshiSpacing.md)
        .padding(.vertical, TodoshiSpacing.sm)
        .frame(minHeight: NavigationHitTargetPolicy.minimumRowHitHeightPoints)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Section tab picker

struct TaskDetailSectionPicker: View {
    @Binding var selection: TaskDetailContentTab
    var commentCount: Int = 0

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(TaskDetailContentTab.allCases) { tab in
                if tab == .comments, commentCount > 0 {
                    Text("\(tab.title) (\(commentCount))").tag(tab)
                } else {
                    Text(tab.title).tag(tab)
                }
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(TodoshiL10n.tr("task.detail.sectionPicker"))
    }
}

// MARK: - Description / notes cards

struct TaskDetailTextCard: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: TodoshiSpacing.xs) {
            Text(title)
                .font(TodoshiTypography.section)
                .foregroundStyle(.primary)
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(TodoshiSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todoshiSurface(cornerRadius: TodoshiRadius.card)
    }
}

// MARK: - Read-only banner

struct TaskDetailReadOnlyBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: TodoshiSpacing.xs) {
            Image(systemName: "lock.fill")
                .font(.caption)
            Text(SharedTaskPermissionPresentation.readOnly)
                .font(TodoshiTypography.metadata.weight(.semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(TodoshiSpacing.sm)
        .todoshiSurface(cornerRadius: TodoshiRadius.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(SharedTaskPermissionPresentation.readOnly). \(message)")
    }
}
