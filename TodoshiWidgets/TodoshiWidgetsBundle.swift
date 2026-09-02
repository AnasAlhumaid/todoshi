import WidgetKit
import SwiftUI

@main
struct NexusWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Project Tasks first so gallery surface prioritizes the project-management widget.
        ProjectTasksWidget()
        TodayTasksWidget()
        HighPriorityWidget()
        NexusQuickAddAccessoryWidget()
        NexusTodayCountAccessoryWidget()
    }
}
