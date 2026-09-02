import Foundation

/// Navigation helpers for search results (pure, testable).
public enum SearchNavigation: Sendable {
    public static func route(forProjectID id: UUID) -> SearchDestination {
        .project(id)
    }

    public static func route(forTaskID id: UUID) -> SearchDestination {
        .task(id)
    }
}

public enum SearchDestination: Equatable, Sendable {
    case project(UUID)
    case task(UUID)
}
