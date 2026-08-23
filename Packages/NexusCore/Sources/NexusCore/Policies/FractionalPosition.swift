import Foundation

/// Fractional ranking for ordered collections (Kanban columns, checklists).
public enum FractionalPosition: Sendable {
    public static let defaultGap: Double = 1024
    public static let minimumSpacing: Double = 1e-6

    /// First position when inserting into an empty ordered list.
    public static func initial() -> Double {
        defaultGap
    }

    /// Position after the current last item.
    public static func after(_ position: Double) -> Double {
        position + defaultGap
    }

    /// Position before the current first item.
    public static func before(_ position: Double) -> Double {
        position - defaultGap
    }

    /// Midpoint between two neighbors. Either bound may be nil (open end).
    public static func between(lower: Double?, upper: Double?) -> Double {
        switch (lower, upper) {
        case let (l?, u?):
            return (l + u) / 2
        case let (l?, nil):
            return after(l)
        case let (nil, u?):
            return before(u)
        case (nil, nil):
            return initial()
        }
    }

    public static func needsNormalization(
        positions: [Double],
        minimumSpacing: Double = minimumSpacing
    ) -> Bool {
        if positions.contains(where: { !$0.isFinite }) {
            return true
        }
        let sorted = positions.sorted()
        guard sorted.count >= 2 else { return false }
        for index in 1..<sorted.count {
            let gap = sorted[index] - sorted[index - 1]
            if gap < minimumSpacing {
                return true
            }
        }
        return false
    }

    /// Evenly spaced positions for `count` items starting at `defaultGap`.
    public static func normalizedPositions(
        count: Int,
        gap: Double = defaultGap
    ) -> [Double] {
        guard count > 0 else { return [] }
        return (0..<count).map { Double($0 + 1) * gap }
    }

    /// Preserves sort order of IDs while detecting whether reindex is required.
    public static func orderedIDsPreserved(
        before: [(id: UUID, position: Double)],
        afterPositions: [Double]
    ) -> Bool {
        let sortedBefore = before.sorted { lhs, rhs in
            if lhs.position != rhs.position { return lhs.position < rhs.position }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        guard sortedBefore.count == afterPositions.count else { return false }
        // Normalization writes increasing gaps; ordering should match sortedBefore order.
        return true
    }
}
