import SwiftUI
import TodoshiCore

struct ProjectRowView: View {
    let project: Project
    let openTaskCount: Int

    var body: some View {
        HStack(spacing: TodoshiSpacing.sm) {
            TodoshiProjectGlyph(systemName: project.icon, colorHex: project.colorHex)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if !project.projectDescription.isEmpty {
                    Text(project.projectDescription)
                        .font(TodoshiTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: TodoshiSpacing.xs)

            Text("\(openTaskCount)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel(TodoshiL10n.plural("widget.openTasksCount", count: openTaskCount))
        }
        .padding(.vertical, TodoshiSpacing.xxs)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [project.name]
        if !project.projectDescription.isEmpty {
            parts.append(project.projectDescription)
        }
        parts.append(TodoshiL10n.plural("widget.openTasksCount", count: openTaskCount))
        return parts.joined(separator: ", ")
    }
}
