import Foundation

/// Documents which controls keep independent hit targets inside navigable cards/rows.
public enum NavigationHitTargetPolicy: Sendable {
  public enum ProjectCardIndependentAction: String, CaseIterable, Sendable {
    case addTask
    case addItem
  }

  public enum TaskRowIndependentAction: String, CaseIterable, Sendable {
    case statusControl
    case contextMenu
    case checklistStatusCycle
  }

  /// Project cards navigate to project detail; task rows navigate to task detail.
  public static func destinationsAreDistinct(projectID: UUID, taskID: UUID) -> Bool {
    projectID != taskID
  }

  public static var minimumRowHitHeightPoints: CGFloat { 44 }
}
