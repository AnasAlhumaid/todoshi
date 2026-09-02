import Foundation

public enum WidgetProjectSelectionDirection: String, Hashable, Sendable {
    case previous
    case next
}

/// Pure previous/next selection among active projects ordered by position.
public enum WidgetProjectSelectionPolicy: Sendable {
    /// Stable order: position ascending, then name.
    public static func orderedActive(_ projects: [WidgetProjectOption]) -> [WidgetProjectOption] {
        projects.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Returns the neighbor of `selectedID` in `ordered` (must already be active+ordered).
    /// Wraps at ends. Missing selection falls back to first for `.next` and last for `.previous`.
    public static func neighbor(
        of selectedID: UUID?,
        in ordered: [WidgetProjectOption],
        direction: WidgetProjectSelectionDirection
    ) -> WidgetProjectOption? {
        guard !ordered.isEmpty else { return nil }
        guard let selectedID,
              let index = ordered.firstIndex(where: { $0.id == selectedID }) else {
            switch direction {
            case .next: return ordered.first
            case .previous: return ordered.last
            }
        }
        switch direction {
        case .next:
            let next = (index + 1) % ordered.count
            return ordered[next]
        case .previous:
            let previous = index == 0 ? ordered.count - 1 : index - 1
            return ordered[previous]
        }
    }

    /// Resolves the project to display: live override if still active, else base configuration, else nil.
    public static func effectiveProjectID(
        baseConfigurationID: UUID?,
        overrideID: UUID?,
        activeIDs: Set<UUID>
    ) -> UUID? {
        if let overrideID, activeIDs.contains(overrideID) {
            return overrideID
        }
        if let baseConfigurationID, activeIDs.contains(baseConfigurationID) {
            return baseConfigurationID
        }
        // Prefer override identity for “deleted/unavailable” messaging when set.
        return overrideID ?? baseConfigurationID
    }
}

/// Result of applying a live project override (widget hamburger selector).
public enum WidgetProjectOverrideResult: Equatable, Sendable {
    case applied(projectID: UUID)
    case invalidBase
    case projectUnavailable
}

/// Validates and persists a per–Edit-Widget base override. Pure + UserDefaults; no UI.
public enum WidgetProjectOverrideApplier: Sendable {
    /// - Parameters:
    ///   - selectedProjectID: Project chosen via App Intent entity picker.
    ///   - baseProjectID: Edit Widget configuration project (override key).
    ///   - activeProjects: Active projects only (may be unsorted).
    ///   - suite: App Group (or test) defaults suite.
    public static func apply(
        selectedProjectID: UUID,
        baseProjectID: UUID?,
        activeProjects: [WidgetProjectOption],
        suite: UserDefaults?
    ) -> WidgetProjectOverrideResult {
        guard let baseProjectID else {
            return .invalidBase
        }
        let ordered = WidgetProjectSelectionPolicy.orderedActive(activeProjects)
        guard ordered.contains(where: { $0.id == selectedProjectID }) else {
            return .projectUnavailable
        }
        guard let suite else {
            return .projectUnavailable
        }
        WidgetProjectSelectionStore.setOverride(selectedProjectID, forBase: baseProjectID, suite: suite)
        return .applied(projectID: selectedProjectID)
    }
}

/// Per–Edit-Widget-slot selection override in the App Group container.
///
/// Keyed by the project originally chosen via **Edit Widget** so each instance that
/// starts from a different configured project keeps its own live override chain.
/// Two instances that share the same base configuration project will share the override (WidgetKit limitation).
public enum WidgetProjectSelectionStore: Sendable {
    public static let suiteName = AppGroupConstants.suiteName
    private static let keyPrefix = "nexus.widget.project.override."

    public static func defaults(suiteName: String = suiteName) -> UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    /// Stable App Group key for a base configuration project (for tests/debug).
    public static func storageKey(forBase baseID: UUID) -> String {
        keyPrefix + baseID.uuidString
    }

    public static func overrideID(
        forBase baseID: UUID,
        suite: UserDefaults? = defaults()
    ) -> UUID? {
        guard let raw = suite?.string(forKey: storageKey(forBase: baseID)) else { return nil }
        return UUID(uuidString: raw)
    }

    public static func setOverride(
        _ projectID: UUID,
        forBase baseID: UUID,
        suite: UserDefaults? = defaults()
    ) {
        suite?.set(projectID.uuidString, forKey: storageKey(forBase: baseID))
    }

    public static func clearOverride(
        forBase baseID: UUID,
        suite: UserDefaults? = defaults()
    ) {
        suite?.removeObject(forKey: storageKey(forBase: baseID))
    }

    public static func effectiveProjectID(
        baseConfigurationID: UUID?,
        suite: UserDefaults? = defaults(),
        activeIDs: Set<UUID>
    ) -> UUID? {
        let override = baseConfigurationID.flatMap { overrideID(forBase: $0, suite: suite) }
        return WidgetProjectSelectionPolicy.effectiveProjectID(
            baseConfigurationID: baseConfigurationID,
            overrideID: override,
            activeIDs: activeIDs
        )
    }
}
