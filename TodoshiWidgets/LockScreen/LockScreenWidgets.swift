import WidgetKit
import SwiftUI
import NexusCore

struct QuickAddAccessoryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: .now, count: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: .now, count: 0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = SimpleEntry(date: .now, count: 0)
        let next = WidgetTimelinePolicy.nextRefreshDate(after: .now)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    struct SimpleEntry: TimelineEntry {
        let date: Date
        let count: Int
    }
}

struct NexusQuickAddAccessoryWidget: Widget {
    let kind = NexusWidgetKind.quickAddAccessory

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickAddAccessoryProvider()) { _ in
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
            }
            .widgetURL(NexusDeepLink.quickAdd.url)
            .containerBackground(for: .widget) {
                AccessoryWidgetBackground()
            }
            .accessibilityLabel(WidgetStrings.quickAdd)
        }
        .configurationDisplayName(NexusL10n.tr("widget.quickAddAccessory"))
        .description(NexusL10n.tr("widget.quickAdd"))
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct TodayCountAccessoryProvider: TimelineProvider {
    func placeholder(in context: Context) -> CountEntry {
        CountEntry(date: .now, count: 3, state: .content)
    }

    func getSnapshot(in context: Context, completion: @escaping (CountEntry) -> Void) {
        Task { @MainActor in
            completion(Self.load())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountEntry>) -> Void) {
        Task { @MainActor in
            let entry = Self.load()
            let next = WidgetTimelinePolicy.nextRefreshDate(after: .now)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    @MainActor
    private static func load() -> CountEntry {
        do {
            // Display limit only truncates listed tasks; totalCount remains full.
            let snapshot = try WidgetSnapshotLoader.loadTodaySnapshot(limit: 1)
            return CountEntry(date: .now, count: snapshot.totalCount, state: .content)
        } catch {
            return CountEntry(date: .now, count: 0, state: .storeUnavailable)
        }
    }

    struct CountEntry: TimelineEntry {
        enum State { case content, storeUnavailable }
        let date: Date
        let count: Int
        let state: State
    }
}

struct NexusTodayCountAccessoryWidget: Widget {
    let kind = NexusWidgetKind.todayCountAccessory

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayCountAccessoryProvider()) { entry in
            Group {
                switch entry.state {
                case .storeUnavailable:
                    Text("—")
                        .font(.headline)
                case .content:
                    VStack(spacing: 2) {
                        Text("\(entry.count)")
                            .font(.headline.monospacedDigit())
                        Text(WidgetStrings.today)
                            .font(.caption2)
                    }
                    .accessibilityLabel(NexusL10n.format("widget.a11yToday", entry.count))
                }
            }
            .widgetURL(NexusDeepLink.dashboard.url)
            .containerBackground(for: .widget) {
                AccessoryWidgetBackground()
            }
        }
        .configurationDisplayName(NexusL10n.tr("widget.todayCount"))
        .description(NexusL10n.tr("widget.todayDesc"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
