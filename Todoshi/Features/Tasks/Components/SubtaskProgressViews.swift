import SwiftUI
import NexusCore

/// Compact subtask progress for root rows and Kanban (`branch 2/4`).
struct SubtaskProgressBadge: View {
    let progress: SubtaskProgress
    var compact: Bool = true

    var body: some View {
        if progress.hasProgress {
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.branch")
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

struct SubtaskProgressHeader: View {
    let progress: SubtaskProgress

    var body: some View {
        if progress.hasProgress {
            Text(progress.accessibilityLabel)
                .font(NexusTypography.metadata)
                .foregroundStyle(.secondary)
        }
    }
}
