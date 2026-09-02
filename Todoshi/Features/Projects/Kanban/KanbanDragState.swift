import Foundation
import Observation
import NexusCore

/// Transient drag visuals only — not a source of truth.
@Observable
@MainActor
final class KanbanDragState {
    var draggedTaskID: UUID?
    var highlightedStatus: TaskStatus?
    var insertionTargetID: UUID?
    /// When true, insert at end of `highlightedStatus`.
    var insertAtEndOfHighlighted = false

    func clear() {
        draggedTaskID = nil
        highlightedStatus = nil
        insertionTargetID = nil
        insertAtEndOfHighlighted = false
    }
}
