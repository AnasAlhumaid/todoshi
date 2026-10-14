import WidgetKit
import SwiftUI

@main
struct TodoshiWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Project Tasks first so gallery surface prioritizes the project-management widget.
        ProjectTasksWidget()
        TodayTasksWidget()
        HighPriorityWidget()
        TodoshiQuickAddAccessoryWidget()
        TodoshiTodayCountAccessoryWidget()
    }
}
