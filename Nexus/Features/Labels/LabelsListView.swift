import SwiftUI
import SwiftData
import NexusCore

struct LabelsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var labels: [LabelTag]
    @State private var isCreating = false
    @State private var editingID: UUID?
    @State private var pendingDelete: LabelTag?
    @State private var deleteError: String?

    private var sorted: [LabelTag] {
        labels.sorted { lhs, rhs in
            let cmp = lhs.name.localizedStandardCompare(rhs.name)
            if cmp != .orderedSame { return cmp == .orderedAscending }
            return lhs.createdAt < rhs.createdAt
        }
    }

    var body: some View {
        List {
            if sorted.isEmpty {
                ContentUnavailableView {
                    Label(LabelStrings.noLabels, systemImage: "tag")
                } description: {
                    Text(NexusL10n.tr("label.emptyHint"))
                } actions: {
                    Button(LabelStrings.createLabel) {
                        isCreating = true
                    }
                }
            } else {
                Section {
                    Text(LabelStrings.listIntro)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                }
                Section {
                    ForEach(sorted, id: \.id) { label in
                        NavigationLink(value: AppRoute.labelTasks(label.id)) {
                            HStack(spacing: NexusSpacing.sm) {
                                Circle()
                                    .fill(NexusColor.from(hex: label.colorHex))
                                    .frame(width: 14, height: 14)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(label.name)
                                        .font(.body.weight(.medium))
                                    Text(taskCountText(for: label))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(accessibilityLabel(for: label))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(LabelStrings.deleteLabel, role: .destructive) {
                                pendingDelete = label
                            }
                            Button(LabelStrings.editLabel) {
                                editingID = label.id
                            }
                            .tint(.accentColor)
                        }
                        .contextMenu {
                            Button(LabelStrings.editLabel) { editingID = label.id }
                            Button(LabelStrings.deleteLabel, role: .destructive) { pendingDelete = label }
                        }
                    }
                }
            }
        }
        .navigationTitle(LabelStrings.labels)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(LabelStrings.createLabel)
            }
        }
        .sheet(isPresented: $isCreating) {
            NavigationStack {
                LabelFormView(context: modelContext)
            }
        }
        .sheet(item: Binding(
            get: { editingID.map(IdentifiedUUID.init) },
            set: { editingID = $0?.id }
        )) { identified in
            NavigationStack {
                LabelFormView(context: modelContext, labelID: identified.id)
            }
        }
        .confirmationDialog(
            LabelStrings.deleteLabel,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let label = pendingDelete {
                Button(LabelStrings.deleteLabel, role: .destructive) {
                    delete(label)
                }
                Button(NexusL10n.tr("common.cancel"), role: .cancel) { pendingDelete = nil }
            }
        } message: {
            if let label = pendingDelete {
                Text(deleteMessage(for: label))
            }
        }
        .alert(NexusL10n.tr("label.unableDelete"), isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button(NexusL10n.tr("common.ok"), role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    private func taskCountText(for label: LabelTag) -> String {
        NexusL10n.plural("count.tasks", count: (label.tasks ?? []).count)
    }

    private func accessibilityLabel(for label: LabelTag) -> String {
        let color = LabelColorCatalog.name(for: label.colorHex)
        return NexusL10n.format("label.a11yAssigned", label.name, color, (label.tasks ?? []).count)
    }

    private func deleteMessage(for label: LabelTag) -> String {
        LabelStrings.deleteConfirmation(name: label.name, taskCount: (label.tasks ?? []).count)
    }

    private func delete(_ label: LabelTag) {
        do {
            try LabelRepository(context: modelContext).delete(labelID: label.id)
            pendingDelete = nil
        } catch {
            deleteError = UserFacingError.message(for: error)
            pendingDelete = nil
        }
    }
}

private struct IdentifiedUUID: Identifiable {
    let id: UUID
}
