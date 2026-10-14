import SwiftUI
import SwiftData
import TodoshiCore

/// Single vertical list for Checklist projects. Rows are root `TaskItem`s.
struct ChecklistProjectListView: View {
    let project: Project
    let snapshot: ChecklistProjectMapping.Snapshot
    let assigneeNames: [String: String]
    let memberCandidates: [AssignmentCandidate]
    let viewerUID: String?
    let isShared: Bool
    let canCreateItems: Bool
    let canEditItem: (TaskItem) -> Bool
    let completionActor: TaskCompletionActor?
    let onPermissionDenied: () -> Void
    let onError: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var draftTitle = ""
    @State private var showsCompleted = true
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        List {
            if !snapshot.isEmpty {
                Section {
                    Text(
                        ProjectTerminologyPolicy.remainingSummary(
                            remaining: snapshot.remainingCount,
                            inProgress: snapshot.inProgressCount,
                            completed: snapshot.completedCount
                        )
                    )
                    .font(TodoshiTypography.metadata)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                }
            }

            if snapshot.isEmpty {
                Section {
                    ContentUnavailableView(
                        ProjectTerminologyPolicy.emptyTitle(.checklist),
                        systemImage: "checklist",
                        description: Text(ProjectTerminologyPolicy.emptyMessage(.checklist))
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(snapshot.activeItems, id: \.id) { item in
                        row(for: item)
                    }
                }

                if !snapshot.completedItems.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showsCompleted) {
                            ForEach(snapshot.completedItems, id: \.id) { item in
                                row(for: item)
                            }
                        } label: {
                            Text(ProjectTerminologyPolicy.completedGroup(snapshot.completedCount))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if canCreateItems {
                Section {
                    HStack(spacing: TodoshiSpacing.sm) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(TodoshiBrand.accent)
                        TextField(
                            ProjectTerminologyPolicy.addItemPlaceholder(.checklist),
                            text: $draftTitle
                        )
                        .focused($addFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { addItem() }
                        if !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button(ProjectTerminologyPolicy.addItem(.checklist)) {
                                addItem()
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
            } else {
                Section {
                    Button {
                        onPermissionDenied()
                    } label: {
                        Label(
                            ProjectTerminologyPolicy.addItem(.checklist),
                            systemImage: "plus.circle"
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func row(for item: TaskItem) -> some View {
        let editable = canEditItem(item)
        let assignee = item.assigneeUID.flatMap { assigneeNames[$0] }
        let completedBy = TaskCompletionPresentation.completedByLine(
            completedByUID: item.completedByUID,
            completedByDisplayName: item.completedByDisplayName,
            members: memberCandidates
        )

        HStack(spacing: TodoshiSpacing.sm) {
            Button {
                advanceStatus(for: item, editable: editable)
            } label: {
                Image(systemName: statusSymbol(item.status))
                    .font(.body.weight(.medium))
                    .foregroundStyle(statusColor(item.status))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(statusCycleAccessibility(for: item))
            .disabled(!editable && item.status == .done)

            NavigationLink(value: AppRoute.task(item.id)) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: TodoshiSpacing.xs) {
                        Text(item.title)
                            .strikethrough(item.status == .done)
                            .foregroundStyle(item.status == .done ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if TaskCollaborationActivityPolicy.hasUnreadActivity(
                            isSharedProject: isShared,
                            task: item,
                            viewerUID: viewerUID
                        ) {
                            TaskUnreadActivityMarker()
                        }
                    }
                    if let assignee {
                        Text(assignee)
                            .font(TodoshiTypography.metadata)
                            .foregroundStyle(.secondary)
                    }
                    if item.status == .done, let completedBy {
                        Text(completedBy)
                            .font(TodoshiTypography.metadata)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: NavigationHitTargetPolicy.minimumRowHitHeightPoints, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.title)
            .accessibilityHint(TodoshiL10n.tr("kanban.opensDetails"))

            Menu {
                ForEach(ProjectTypeCapabilities.allowedStatuses(for: .checklist), id: \.self) { status in
                    Button(ProjectStatusPolicy.displayName(status, for: .checklist)) {
                        setStatus(status, for: item, editable: editable)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .disabled(!editable)
        }
        .accessibilityElement(children: .contain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if editable {
                Button(role: .destructive) {
                    delete(item)
                } label: {
                    Label(TodoshiL10n.tr("common.delete"), systemImage: "trash")
                }
            }
        }
    }

    private func statusSymbol(_ status: TaskStatus) -> String {
        switch status {
        case .todo, .backlog, .review: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        }
    }

    private func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .todo, .backlog, .review: return TodoshiBrand.secondaryText
        case .inProgress: return TodoshiStatusColor.indicator(for: .inProgress)
        case .done: return TodoshiStatusColor.indicator(for: .done)
        }
    }

    private func statusCycleAccessibility(for item: TaskItem) -> String {
        switch item.status {
        case .todo: return ProjectTerminologyPolicy.trMarkInProgress
        case .inProgress: return ProjectTerminologyPolicy.trMarkCompleted
        case .done: return ProjectTerminologyPolicy.trReopen
        default: return ProjectStatusPolicy.displayName(item.status, for: .checklist)
        }
    }

    /// Primary control: todo → inProgress → done. Completed items reopen only via the status menu.
    private func advanceStatus(for item: TaskItem, editable: Bool) {
        guard editable else {
            onPermissionDenied()
            return
        }
        guard let next = ProjectStatusPolicy.nextChecklistCycle(from: item.status) else { return }
        setStatus(next, for: item, editable: true)
    }

    private func setStatus(_ status: TaskStatus, for item: TaskItem, editable: Bool) {
        guard editable else {
            onPermissionDenied()
            return
        }
        guard ProjectTypeCapabilities.allowsStatus(status, for: .checklist) else { return }
        do {
            _ = try TaskRepository(context: modelContext).move(
                taskID: item.id,
                to: status,
                before: nil,
                completionActor: completionActor
            )
        } catch {
            onError(UserFacingError.message(for: error))
        }
    }

    private func addItem() {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard canCreateItems else {
            onPermissionDenied()
            return
        }
        do {
            _ = try TaskRepository(context: modelContext).create(
                in: project,
                title: title,
                status: ProjectTypeCapabilities.defaultStatus(for: .checklist)
            )
            draftTitle = ""
            addFieldFocused = true
        } catch {
            onError(UserFacingError.message(for: error))
        }
    }

    private func delete(_ item: TaskItem) {
        do {
            try TaskRepository(context: modelContext).delete(item, mode: .deleteDescendants)
        } catch {
            onError(UserFacingError.message(for: error))
        }
    }
}

private extension ProjectTerminologyPolicy {
    static var trMarkInProgress: String { TodoshiL10n.tr("project.checklist.markInProgress") }
    static var trMarkCompleted: String { TodoshiL10n.tr("project.checklist.markCompleted") }
    static var trReopen: String { TodoshiL10n.tr("project.checklist.reopen") }
}
