import WidgetKit
import SwiftUI
import NexusCore

struct TodayTasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> NexusWidgetEntry {
        NexusWidgetEntry(date: .now, snapshot: WidgetPreviewData.today(), state: .content)
    }

    func getSnapshot(in context: Context, completion: @escaping (NexusWidgetEntry) -> Void) {
        Task { @MainActor in
            completion(Self.loadEntry(now: .now, limit: 3))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NexusWidgetEntry>) -> Void) {
        Task { @MainActor in
            let entry = Self.loadEntry(now: .now, limit: 6)
            completion(NexusWidgetTimeline.timeline(for: entry))
        }
    }

    @MainActor
    private static func loadEntry(now: Date, limit: Int) -> NexusWidgetEntry {
        do {
            let snapshot = try WidgetSnapshotLoader.loadTodaySnapshot(referenceDate: now, limit: limit)
            let state: WidgetLoadState = snapshot.totalCount == 0 ? .empty : .content
            return NexusWidgetEntry(date: now, snapshot: snapshot, state: state)
        } catch {
            return NexusWidgetEntry(
                date: now,
                snapshot: .unavailable(title: WidgetStrings.today, generatedAt: now),
                state: .storeUnavailable
            )
        }
    }
}

struct TodayTasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: NexusWidgetEntry

    var body: some View {
        Group {
            switch entry.state {
            case .storeUnavailable:
                WidgetEmptyView(title: WidgetStrings.today, message: WidgetStrings.openNexus)
            case .empty:
                WidgetEmptyView(title: WidgetStrings.today, message: WidgetStrings.nothingToday)
                    .overlay(alignment: .bottomTrailing) {
                        WidgetQuickAddBadge().padding()
                    }
            default:
                content
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
        .widgetURL(NexusDeepLink.dashboard.url)
    }

    @ViewBuilder
    private var content: some View {
        let limit = family == .systemSmall ? 1 : (family == .systemMedium ? 3 : 6)
        let shown = Array(entry.snapshot.tasks.prefix(limit))

        WidgetListChrome(
            title: WidgetStrings.today,
            count: entry.snapshot.totalCount,
            headerLink: NexusDeepLink.dashboard.url
        ) {
            if family == .systemSmall {
                if let first = shown.first {
                    WidgetTaskRowView(task: first, showProject: false)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(shown) { task in
                        WidgetTaskRowView(task: task)
                    }
                    if entry.snapshot.totalCount > shown.count {
                        Text(WidgetStrings.remaining(entry.snapshot.totalCount - shown.count))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityLabel(NexusL10n.format("widget.a11yToday", entry.snapshot.totalCount))
    }
}

struct TodayTasksWidget: Widget {
    let kind = NexusWidgetKind.today

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayTasksProvider()) { entry in
            TodayTasksWidgetView(entry: entry)
        }
        .configurationDisplayName(NexusL10n.tr("widget.today"))
        .description(NexusL10n.tr("widget.todayDesc"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
