import WidgetKit
import SwiftUI
import TodoshiCore

struct HighPriorityProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoshiWidgetEntry {
        TodoshiWidgetEntry(date: .now, snapshot: WidgetPreviewData.today(), state: .content)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoshiWidgetEntry) -> Void) {
        Task { @MainActor in
            completion(Self.loadEntry(now: .now, limit: 3))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoshiWidgetEntry>) -> Void) {
        Task { @MainActor in
            let entry = Self.loadEntry(now: .now, limit: 6)
            completion(TodoshiWidgetTimeline.timeline(for: entry))
        }
    }

    @MainActor
    private static func loadEntry(now: Date, limit: Int) -> TodoshiWidgetEntry {
        do {
            let snapshot = try WidgetSnapshotLoader.loadHighPrioritySnapshot(referenceDate: now, limit: limit)
            let state: WidgetLoadState = snapshot.totalCount == 0 ? .empty : .content
            return TodoshiWidgetEntry(date: now, snapshot: snapshot, state: state)
        } catch {
            return TodoshiWidgetEntry(
                date: now,
                snapshot: .unavailable(title: WidgetStrings.highPriority, generatedAt: now),
                state: .storeUnavailable
            )
        }
    }
}

struct HighPriorityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TodoshiWidgetEntry

    var body: some View {
        Group {
            switch entry.state {
            case .storeUnavailable:
                WidgetEmptyView(title: WidgetStrings.highPriority, message: WidgetStrings.openTodoshi)
            case .empty:
                WidgetEmptyView(title: WidgetStrings.highPriority, message: WidgetStrings.noHighPriority)
            default:
                content
            }
        }
        .fontDesign(.rounded)
        // Follow the in-app language direction, which can differ from the system's.
        .environment(\.layoutDirection, AppLanguageStore.isRightToLeft ? .rightToLeft : .leftToRight)
        .containerBackground(for: .widget) {
            WidgetTheme.canvas
        }
        .widgetURL(TodoshiDeepLink.dashboard.url)
    }

    @ViewBuilder
    private var content: some View {
        let limit = family == .systemSmall ? 1 : (family == .systemMedium ? 3 : 6)
        let shown = Array(entry.snapshot.tasks.prefix(limit))
        WidgetListChrome(
            title: WidgetStrings.highPriority,
            count: entry.snapshot.totalCount,
            headerLink: TodoshiDeepLink.dashboard.url
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shown) { task in
                    WidgetTaskRowView(task: task, showProject: family != .systemSmall)
                }
                if entry.snapshot.totalCount > shown.count {
                    Text(WidgetStrings.remaining(entry.snapshot.totalCount - shown.count))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityLabel(TodoshiL10n.format("widget.a11yHighPriority", entry.snapshot.totalCount))
    }
}

struct HighPriorityWidget: Widget {
    let kind = TodoshiWidgetKind.highPriority

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HighPriorityProvider()) { entry in
            HighPriorityWidgetView(entry: entry)
        }
        .configurationDisplayName(TodoshiL10n.tr("widget.highPriority"))
        .description(TodoshiL10n.tr("widget.highPriorityDesc"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
