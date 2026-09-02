import AppIntents
import Foundation
import SwiftData
import WidgetKit
import NexusCore

// MARK: - Project selection (system App Intent picker)

/// Prompts for an active project via the system App Intent UI and stores a live override.
/// Does not open the main app. Does not change the Edit Widget base configuration.
struct SelectWidgetProjectIntent: AppIntent {
    // App Intents metadata requires string-literal LocalizedStringResource initializers.
    static var title: LocalizedStringResource = "intent.selectProject.title"
    static var description = IntentDescription("intent.selectProject.desc")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "widget.project")
    var project: NexusProjectEntity?

    /// Edit Widget configuration project — override key. Not shown in the primary summary.
    @Parameter(title: "intent.baseConfigProject")
    var baseProjectID: String

    init() {
        self.project = nil
        self.baseProjectID = ""
    }

    /// Widget button: base only; system prompts for `project`.
    init(baseProjectID: UUID) {
        self.project = nil
        self.baseProjectID = baseProjectID.uuidString
    }

    static var parameterSummary: some ParameterSummary {
        Summary("intent.selectProject.summary") {
            \.$project
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard WidgetQuickAddService.createsFallbackStoreOnSharedFailure == false else {
            return .result(dialog: IntentDialog(stringLiteral: NexusL10n.tr("intent.unableChangeProject")))
        }
        guard let baseID = UUID(uuidString: baseProjectID) else {
            return .result(dialog: IntentDialog(stringLiteral: NexusL10n.tr("intent.unableChangeProject")))
        }

        let selected: NexusProjectEntity
        if let project {
            selected = project
        } else {
            // System entity picker (Active projects from EntityQuery.suggestedEntities).
            selected = try await $project.requestValue(
                IntentDialog(stringLiteral: NexusL10n.tr("intent.selectProject.prompt"))
            )
        }

        do {
            let container = try WidgetStoreAccess.makeSharedContainer()
            let context = ModelContext(container)
            let active = try WidgetStoreAccess.loadActiveProjects(from: context)
            let suite = WidgetProjectSelectionStore.defaults()

            switch WidgetProjectOverrideApplier.apply(
                selectedProjectID: selected.id,
                baseProjectID: baseID,
                activeProjects: active,
                suite: suite
            ) {
            case .applied:
                for kind in WidgetReloadClassifier.kinds(for: .widgetProjectSelectionChanged) {
                    WidgetCenter.shared.reloadTimelines(ofKind: kind)
                }
                return .result(dialog: IntentDialog(stringLiteral: NexusL10n.tr("intent.projectSelected")))
            case .invalidBase, .projectUnavailable:
                return .result(dialog: IntentDialog(stringLiteral: NexusL10n.tr("intent.projectUnavailable")))
            }
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: NexusL10n.tr("intent.unableChangeProject")))
        }
    }
}

// MARK: - Project cycling (retained for tests / internal use; not shown in Project widget UI)

/// Cycles the Project Tasks widget selection among active projects (position order, wrap-around).
struct SwitchConfiguredProjectIntent: AppIntent {
    static var title: LocalizedStringResource = "intent.switchProject.title"
    static var description = IntentDescription("intent.switchProject.desc")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "intent.baseConfigProject")
    var baseConfigurationProjectID: String

    @Parameter(title: "intent.displayedProject")
    var displayedProjectID: String

    @Parameter(title: "intent.direction")
    var directionRaw: String

    init() {
        self.baseConfigurationProjectID = ""
        self.displayedProjectID = ""
        self.directionRaw = WidgetProjectSelectionDirection.next.rawValue
    }

    init(
        baseConfigurationProjectID: UUID,
        displayedProjectID: UUID?,
        direction: WidgetProjectSelectionDirection
    ) {
        self.baseConfigurationProjectID = baseConfigurationProjectID.uuidString
        self.displayedProjectID = displayedProjectID?.uuidString ?? ""
        self.directionRaw = direction.rawValue
    }

    static var parameterSummary: some ParameterSummary {
        Summary("intent.switchParamSummary") {
            \.$directionRaw
            \.$baseConfigurationProjectID
            \.$displayedProjectID
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let baseID = UUID(uuidString: baseConfigurationProjectID) else {
            return .result()
        }
        let direction = WidgetProjectSelectionDirection(rawValue: directionRaw) ?? .next
        let displayed = UUID(uuidString: displayedProjectID)

        do {
            let container = try WidgetStoreAccess.makeSharedContainer()
            let context = ModelContext(container)
            let ordered = WidgetProjectSelectionPolicy.orderedActive(
                try WidgetStoreAccess.loadActiveProjects(from: context)
            )
            guard let next = WidgetProjectSelectionPolicy.neighbor(
                of: displayed,
                in: ordered,
                direction: direction
            ) else {
                return .result()
            }
            WidgetProjectSelectionStore.setOverride(next.id, forBase: baseID)
            for kind in WidgetReloadClassifier.kinds(for: .widgetProjectSelectionChanged) {
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }
        } catch {
            // Shared store unavailable — leave selection unchanged.
        }
        return .result()
    }
}

// MARK: - Quick Add

struct AddTaskToSelectedProjectIntent: AppIntent {
    static var title: LocalizedStringResource = "intent.addTask.title"
    static var description = IntentDescription("intent.addTask.desc")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "intent.taskTitle")
    var title: String

    @Parameter(title: "intent.projectID")
    var projectID: String

    @Parameter(title: "intent.projectName")
    var projectName: String

    init() {
        self.title = ""
        self.projectID = ""
        self.projectName = ""
    }

    init(title: String = "", projectID: UUID, projectName: String) {
        self.title = title
        self.projectID = projectID.uuidString
        self.projectName = projectName
    }

    static var parameterSummary: some ParameterSummary {
        Summary("intent.paramSummary") {
            \.$title
            \.$projectName
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard WidgetQuickAddService.createsFallbackStoreOnSharedFailure == false else {
            return .result(dialog: IntentDialog(stringLiteral: NexusL10n.tr("intent.cannotWithoutStore")))
        }
        guard let pid = UUID(uuidString: projectID) else {
            return .result(dialog: IntentDialog(stringLiteral: NexusL10n.tr("intent.projectUnavailable")))
        }

        do {
            let container = try WidgetStoreAccess.makeSharedContainer()
            let context = ModelContext(container)
            _ = try WidgetQuickAddService.createRootTask(
                title: title,
                projectID: pid,
                context: context
            )
            for kind in WidgetReloadClassifier.kinds(for: .widgetTaskCreated) {
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }
            return .result(dialog: IntentDialog(stringLiteral: NexusL10n.tr("intent.taskAdded")))
        } catch WidgetQuickAddService.Error.emptyTitle {
            return .result(dialog: IntentDialog(stringLiteral: NexusL10n.tr("intent.enterTitle")))
        } catch WidgetQuickAddService.Error.projectUnavailable {
            return .result(dialog: IntentDialog(stringLiteral: NexusL10n.tr("intent.projectUnavailable")))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: NexusL10n.tr("intent.openSetup")))
        }
    }
}

// MARK: - App Shortcuts

struct NexusWidgetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskToSelectedProjectIntent(),
            phrases: [
                "Add task in \(.applicationName)",
                "Add a task to \(.applicationName)",
                "أضف مهمة في \(.applicationName)",
                "أضف مهمة إلى \(.applicationName)"
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )
    }
}
