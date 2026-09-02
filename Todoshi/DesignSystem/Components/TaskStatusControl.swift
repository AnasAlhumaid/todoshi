import SwiftUI
import NexusCore

enum TaskStatusControlStyle {
    /// Full status label for boards outside the matching section context.
    case labeled
    /// Compact “change status” action when section already shows the status.
    case sectionCompact
    /// Dot-only control for dense Home rows.
    case homeIndicator
}

struct TaskStatusControl: View {
    let currentStatus: TaskStatus
    var style: TaskStatusControlStyle
    var sectionStatus: TaskStatus? = nil
    let onSelect: (TaskStatus) -> Void

    var body: some View {
        Menu {
            statusMenuItems
        } label: {
            controlLabel
                .frame(minHeight: NexusIconSize.hit, alignment: .leading)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(NexusL10n.tr("task.statusControl.hint"))
    }

    @ViewBuilder
    private var controlLabel: some View {
        switch style {
        case .labeled:
            labeledControl(showFullStatus: true)
        case .sectionCompact:
            labeledControl(showFullStatus: false)
        case .homeIndicator:
            HStack(spacing: NexusSpacing.xxs) {
                Circle()
                    .fill(NexusStatusColor.indicator(for: currentStatus))
                    .frame(width: 10, height: 10)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, NexusSpacing.xxs)
        }
    }

    private func labeledControl(showFullStatus: Bool) -> some View {
        HStack(spacing: NexusSpacing.xxs) {
            Circle()
                .fill(NexusStatusColor.indicator(for: currentStatus))
                .frame(width: 8, height: 8)

            Text(showFullStatus ? currentStatus.displayName : NexusL10n.tr("task.changeStatus"))
                .font(NexusTypography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var statusMenuItems: some View {
        ForEach(TaskStatus.allCases, id: \.self) { status in
            Button {
                guard status != currentStatus else { return }
                onSelect(status)
            } label: {
                if status == currentStatus {
                    Label(status.displayName, systemImage: "checkmark")
                } else {
                    Text(status.displayName)
                }
            }
        }
    }

    private var accessibilityLabelText: String {
        NexusL10n.format("task.statusControl.a11y", currentStatus.displayName)
    }

    static func style(for taskStatus: TaskStatus, sectionStatus: TaskStatus?) -> TaskStatusControlStyle {
        if taskStatus == sectionStatus {
            return .sectionCompact
        }
        return .labeled
    }
}
