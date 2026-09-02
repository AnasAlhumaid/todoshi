import WidgetKit
import SwiftUI
import NexusCore

struct HighPriorityProvider: TimelineProvider {
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
            let snapshot = try WidgetSnapshotLoader.loadHighPrioritySnapshot(referenceDate: now, limit: limit)
            let state: WidgetLoadState = snapshot.totalCount == 0 ? .empty : .content
            return NexusWidgetEntry(date: now, snapshot: snapshot, state: state)
        } catch {
            return NexusWidgetEntry(
                date: now,
                snapshot: .unavailable(title: WidgetStrings.highPriority, generatedAt: now),
                state: .storeUnavailable
            )
        }
    }
}

struct HighPriorityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: NexusWidgetEntry

    var body: some View {
        Group {
            switch entry.state {
            case .storeUnavailable:
                WidgetEmptyView(title: WidgetStrings.highPriority, message: WidgetStrings.openNexus)
            case .empty:
                WidgetEmptyView(title: WidgetStrings.highPriority, message: WidgetStrings.noHighPriority)
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
            title: WidgetStrings.highPriority,
            count: entry.snapshot.totalCount,
            headerLink: NexusDeepLink.dashboard.url
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
        .accessibilityLabel(NexusL10n.format("widget.a11yHighPriority", entry.snapshot.totalCount))
    }
}

struct HighPriorityWidget: Widget {
    let kind = NexusWidgetKind.highPriority

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HighPriorityProvider()) { entry in
            HighPriorityWidgetView(entry: entry)
        }
        .configurationDisplayName(NexusL10n.tr("widget.highPriority"))
        .description(NexusL10n.tr("widget.highPriorityDesc"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
