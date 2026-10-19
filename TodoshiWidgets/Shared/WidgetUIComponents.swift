import SwiftUI
import WidgetKit
import TodoshiCore

/// Widget palette mirroring the app's TodoshiBrand tokens (the extension has no shared asset catalog).
enum WidgetTheme {
    static let accent = adaptive(
        light: UIColor(red: 0.322, green: 0.282, blue: 0.851, alpha: 1),
        dark: UIColor(red: 0.482, green: 0.451, blue: 0.910, alpha: 1)
    )
    static let canvas = adaptive(
        light: UIColor(red: 0.965, green: 0.961, blue: 0.984, alpha: 1),
        dark: UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
    )
    static let card = adaptive(
        light: .white,
        dark: UIColor(red: 0.13, green: 0.13, blue: 0.16, alpha: 1)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// Date/time text in the in-app language. Formatted to a String up front because widget
/// `Text(date, …)` follows the extension's own localization, which ignores the app override.
enum WidgetDateText {
    static func dayMonth(_ date: Date) -> String {
        formatter(template: "dMMM").string(from: date)
    }

    static func time(_ date: Date) -> String {
        formatter(template: "jmm").string(from: date)
    }

    private static func formatter(template: String) -> DateFormatter {
        let locale = AppLanguageStore.resolvedLocale
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}

/// Count capsule used in widget headers.
struct WidgetCountPill: View {
    let count: Int
    var tint: Color = WidgetTheme.accent

    var body: some View {
        Text(count, format: .number)
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

struct WidgetTaskRowView: View {
    let task: WidgetTaskItem
    var showProject: Bool = true
    @Environment(\.widgetFamily) private var family

    /// Medium has room for three single-line rows only; the colored dot carries the project.
    private var isCompact: Bool { family == .systemMedium || family == .systemSmall }

    var body: some View {
        Link(destination: TodoshiDeepLink.task(task.id).url) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .strokeBorder(task.isOverdue ? Color.red : Color.secondary.opacity(0.45), lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .privacySensitive()
                    if !isCompact || task.isOverdue {
                        HStack(spacing: 4) {
                            if task.isOverdue {
                                Text(TodoshiL10n.tr("common.overdue"))
                                    .foregroundStyle(.red)
                            } else if showProject {
                                Text(task.projectName)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else if let due = task.dueDate {
                                Text(WidgetDateText.time(due))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption2)
                    }
                }
                Spacer(minLength: 0)
                if showProject {
                    Circle()
                        .fill(Color(hex: task.projectColorHex))
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
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
        if task.isOverdue { parts.append(TodoshiL10n.tr("common.overdue")) }
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
    var deepLink: URL = TodoshiDeepLink.dashboard.url

    var body: some View {
        Link(destination: deepLink) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(WidgetTheme.accent)
                Spacer(minLength: 0)
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(WidgetTheme.accent.opacity(0.35))
                    .accessibilityHidden(true)
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct WidgetQuickAddBadge: View {
    var body: some View {
        Link(destination: TodoshiDeepLink.quickAdd().url) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(WidgetTheme.accent, in: Circle())
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
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        WidgetCountPill(count: count)
                            .accessibilityLabel(WidgetStrings.tasksCount(count))
                    }
                }
                Spacer()
                WidgetQuickAddBadge()
            }
            content()
            Spacer(minLength: 0)
        }
    }
}
