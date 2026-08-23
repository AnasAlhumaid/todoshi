import Foundation

/// Centralized user-facing label strings.
public enum LabelStrings: Sendable {
    public static var labels: String { NexusL10n.tr("label.labels") }
    public static var createLabel: String { NexusL10n.tr("label.create") }
    public static var createNewLabel: String { NexusL10n.tr("label.createNew") }
    public static var newLabel: String { NexusL10n.tr("label.new") }
    public static var addLabel: String { NexusL10n.tr("label.add") }
    public static var editLabel: String { NexusL10n.tr("label.edit") }
    public static var editSelected: String { NexusL10n.tr("label.editSelected") }
    public static var deleteLabel: String { NexusL10n.tr("label.delete") }
    public static var assignedTasks: String { NexusL10n.tr("label.assignedTasks") }
    public static var duplicateName: String { NexusL10n.tr("label.duplicateName") }
    public static var name: String { NexusL10n.tr("label.name") }
    public static var namePlaceholder: String { NexusL10n.tr("label.namePlaceholder") }
    public static var nameRequired: String { NexusL10n.tr("label.nameRequired") }
    public static var nameTooLong: String {
        NexusL10n.format("label.nameTooLong", LabelValidation.maxNameLength)
    }
    public static var invalidColor: String { NexusL10n.tr("label.invalidColor") }
    public static var noLabels: String { NexusL10n.tr("label.noLabels") }
    public static var noMatches: String { NexusL10n.tr("label.noMatches") }
    public static var selectLabels: String { NexusL10n.tr("label.selectLabels") }
    public static var listIntro: String { NexusL10n.tr("label.listIntro") }
    public static var formHint: String { NexusL10n.tr("label.formHint") }
    public static var removeLabel: String { NexusL10n.tr("label.remove") }
    public static var noAssignedTasks: String { NexusL10n.tr("label.noAssigned") }

    public static var deleteConfirmationFormat: String { NexusL10n.tr("label.deleteConfirm") }
    public static var deleteUnassignedConfirmationFormat: String { NexusL10n.tr("label.deleteUnassigned") }

    public static func deleteConfirmation(name: String, taskCount: Int, locale: Locale = .autoupdatingCurrent) -> String {
        if taskCount == 0 {
            return NexusL10n.format("label.deleteUnassigned", locale: locale, name)
        }
        return NexusL10n.format("label.deleteConfirm", locale: locale, name, taskCount)
    }
}
