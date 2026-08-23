import Foundation
import WidgetKit
import NexusCore

/// App-layer coordinator — call after successful repository writes.
@MainActor
enum WidgetReloadCoordinator {
    static func reload(for event: WidgetReloadClassifier.Event) {
        let kinds = WidgetReloadClassifier.kinds(for: event)
        let center = WidgetCenter.shared
        for kind in kinds {
            center.reloadTimelines(ofKind: kind)
        }
    }

    static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
