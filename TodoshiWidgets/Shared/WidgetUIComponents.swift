import SwiftUI
import NexusCore

struct WidgetTaskRowView: View {
    let task: WidgetTaskItem
    var showProject: Bool = true

    var body: some View {
        Link(destination: NexusDeepLink.task(task.id).url) {
            HStack(alignment: .top, spacing: 8) {
                if showProject {
                    Image(systemName: task.projectIcon)
                        .font(.caption)
                        .foregroundStyle(Color(hex: task.projectColorHex))
                        .frame(width: 14)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .privacySensitive()
                    HStack(spacing: 4) {
                        if showProject {
                            Text(task.projectName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if task.isOverdue {
                            Text(NexusL10n.tr("common.overdue"))
                                .font(.caption2)
                                .foregroundStyle(.red)
                        } else if let due = task.dueDate {
                            Text(due, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [task.title]
        if showProject { parts.append(task.projectName) }
        if task.priority == .urgent || task.priority == .high {
            parts.append(task.priority.displayName)
        }
        if task.isOverdue { parts.append(NexusL10n.tr("common.overdue")) }
        return parts.joined(separator: ", ")
    }
}

extension Color {
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

struct WidgetEmptyView: View {
    let title: String
    let message: String
    var deepLink: URL = NexusDeepLink.dashboard.url

    var body: some View {
        Link(destination: deepLink) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct WidgetQuickAddBadge: View {
    var body: some View {
        Link(destination: NexusDeepLink.quickAdd.url) {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .accessibilityLabel(WidgetStrings.quickAdd)
        }
    }
}

struct WidgetListChrome<Content: View>: View {
    let title: String
    let count: Int
    let headerLink: URL
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Link(destination: headerLink) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(WidgetStrings.tasksCount(count))
                    }
                }
                Spacer()
                WidgetQuickAddBadge()
            }
            content()
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}
