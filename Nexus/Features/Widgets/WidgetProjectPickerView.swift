import SwiftUI
import SwiftData
import NexusCore

/// Lightweight picker opened from the Project Tasks widget hamburger deep link.
struct WidgetProjectPickerView: View {
    let baseProjectID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var projects: [Project]

    @State private var query = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private static let searchThreshold = 8

    init(baseProjectID: UUID?) {
        self.baseProjectID = baseProjectID
        let active = ProjectStatus.active.rawValue
        _projects = Query(
            filter: #Predicate<Project> { $0.statusRaw == active },
            sort: [
                SortDescriptor(\Project.position),
                SortDescriptor(\Project.name)
            ]
        )
    }

    private var orderedProjects: [Project] {
        projects.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var filteredProjects: [Project] {
        let base = orderedProjects
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return base.filter { $0.name.localizedStandardContains(trimmed) }
    }

    private var showsSearch: Bool {
        orderedProjects.count >= Self.searchThreshold
    }

    private var currentDisplayedID: UUID? {
        guard let baseProjectID else { return nil }
        let activeIDs = Set(orderedProjects.map(\.id))
        return WidgetProjectSelectionStore.effectiveProjectID(
            baseConfigurationID: baseProjectID,
            activeIDs: activeIDs
        )
    }

    var body: some View {
        Group {
            if baseProjectID == nil {
                ContentUnavailableView(
                    NexusL10n.tr("widgetPicker.unableIdentify"),
                    systemImage: "exclamationmark.triangle"
                )
            } else if orderedProjects.isEmpty {
                ContentUnavailableView(
                    NexusL10n.tr("widget.noActiveProjects"),
                    systemImage: "folder"
                )
            } else {
                projectList
            }
        }
        .navigationTitle(NexusL10n.tr("widget.selectProject"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NexusL10n.tr("common.close")) { dismiss() }
            }
        }
        .alert(
            NexusL10n.tr("common.somethingWrong"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(NexusL10n.tr("common.ok"), role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var projectList: some View {
        List {
            ForEach(filteredProjects, id: \.id) { project in
                Button {
                    select(project)
                } label: {
                    projectRow(project)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .accessibilityLabel(rowAccessibility(project))
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if filteredProjects.isEmpty {
                ContentUnavailableView.search
            }
        }
        .modifier(OptionalSearchModifier(
            enabled: showsSearch,
            text: $query,
            prompt: NexusL10n.tr("search.prompt")
        ))
    }

    @ViewBuilder
    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: NexusSpacing.md) {
            Image(systemName: project.icon)
                .font(.body.weight(.medium))
                .foregroundStyle(NexusColor.from(hex: project.colorHex))
                .frame(width: NexusIconSize.glyph, height: NexusIconSize.glyph)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(NexusL10n.plural(
                    "widget.openTasksCount",
                    count: ProjectTaskCounts.openRootCount(tasks: project.tasks ?? [])
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if project.id == currentDisplayedID {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel(NexusL10n.tr("common.selected"))
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private func rowAccessibility(_ project: Project) -> String {
        var parts = [project.name]
        let count = ProjectTaskCounts.openRootCount(tasks: project.tasks ?? [])
        parts.append(NexusL10n.plural("widget.openTasksCount", count: count))
        if project.id == currentDisplayedID {
            parts.append(NexusL10n.tr("common.selected"))
        }
        return parts.joined(separator: ", ")
    }

    private func select(_ project: Project) {
        guard let baseProjectID else {
            errorMessage = NexusL10n.tr("widgetPicker.unableIdentify")
            return
        }
        guard project.status == .active else {
            errorMessage = NexusL10n.tr("widget.projectUnavailable")
            return
        }

        isSaving = true
        let options = orderedProjects.map {
            WidgetProjectOption(
                id: $0.id,
                name: $0.name,
                icon: $0.icon,
                colorHex: $0.colorHex,
                position: $0.position
            )
        }

        let result = WidgetProjectOverrideApplier.apply(
            selectedProjectID: project.id,
            baseProjectID: baseProjectID,
            activeProjects: options,
            suite: WidgetProjectSelectionStore.defaults()
        )

        switch result {
        case .applied:
            WidgetReloadCoordinator.reload(for: .widgetProjectSelectionChanged)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        case .invalidBase:
            errorMessage = NexusL10n.tr("widgetPicker.unableIdentify")
            isSaving = false
        case .projectUnavailable:
            errorMessage = NexusL10n.tr("widget.projectUnavailable")
            isSaving = false
        }
    }
}

/// Conditionally applies searchable to avoid empty search chrome for small lists.
private struct OptionalSearchModifier: ViewModifier {
    let enabled: Bool
    @Binding var text: String
    let prompt: String

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, prompt: Text(prompt))
        } else {
            content
        }
    }
}

#Preview {
    NavigationStack {
        WidgetProjectPickerView(baseProjectID: UUID())
    }
    .modelContainer(try! ModelContainerFactory.makeContainer(kind: .inMemory))
}
