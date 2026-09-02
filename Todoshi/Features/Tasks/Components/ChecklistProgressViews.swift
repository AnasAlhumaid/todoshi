import SwiftUI
import NexusCore

/// Compact checklist progress for rows and Kanban cards (`☑ 3/5`).
struct ChecklistProgressBadge: View {
    let progress: ChecklistProgress
    var compact: Bool = true

    var body: some View {
        if progress.hasProgress {
            HStack(spacing: 3) {
                Image(systemName: progress.isComplete ? "checkmark.square.fill" : "checkmark.square")
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(progress.compactLabel)
                    .font(compact ? .caption2.monospacedDigit() : .caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(progress.accessibilityLabel)
        }
    }
}

/// Progress bar + text for Task Detail checklist section.
struct ChecklistProgressHeader: View {
    let progress: ChecklistProgress

    var body: some View {
        if progress.hasProgress {
            Text(progress.accessibilityLabel)
                .font(NexusTypography.metadata)
                .foregroundStyle(.secondary)
                .accessibilityLabel(progress.accessibilityLabel)
        }
    }
}
