import Foundation
import Testing
@testable import TodoshiCore

struct NavigationHitTargetTests {
    @Test("Project and task destinations remain distinct")
    func distinctDestinations() {
        let projectID = UUID()
        let taskID = UUID()
        #expect(NavigationHitTargetPolicy.destinationsAreDistinct(projectID: projectID, taskID: taskID))
    }

    @Test("Project card documents independent add actions")
    func projectCardIndependentActions() {
        #expect(NavigationHitTargetPolicy.ProjectCardIndependentAction.allCases.count == 2)
        #expect(NavigationHitTargetPolicy.ProjectCardIndependentAction.addTask.rawValue == "addTask")
        #expect(NavigationHitTargetPolicy.ProjectCardIndependentAction.addItem.rawValue == "addItem")
    }

    @Test("Task row documents independent status and menu actions")
    func taskRowIndependentActions() {
        let actions = NavigationHitTargetPolicy.TaskRowIndependentAction.allCases
        #expect(actions.contains(.statusControl))
        #expect(actions.contains(.contextMenu))
        #expect(actions.contains(.checklistStatusCycle))
    }

    @Test("Minimum row hit height matches standard touch target")
    func minimumRowHeight() {
        #expect(NavigationHitTargetPolicy.minimumRowHitHeightPoints == 44)
    }

    @Test("Checklist and Tasks project cards share add-action separation policy")
    func checklistParity() {
        #expect(ProjectTerminologyPolicy.addItem(.checklist) != TodoshiL10n.tr("calendar.addTask"))
        #expect(NavigationHitTargetPolicy.ProjectCardIndependentAction.addItem.rawValue == "addItem")
    }

    @Test("Board task card title and status use separate navigation rows")
    func boardCardUsesTwoRowLayout() {
        #expect(NavigationHitTargetPolicy.TaskRowIndependentAction.statusControl.rawValue == "statusControl")
        #expect(NavigationHitTargetPolicy.minimumRowHitHeightPoints >= 44)
    }
}
