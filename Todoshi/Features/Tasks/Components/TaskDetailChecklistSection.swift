import SwiftUI
import SwiftData
import UIKit
import NexusCore

/// Immediate-persistence checklist section for Task Detail.
struct TaskDetailChecklistSection: View {
    let taskID: UUID
    let items: [ChecklistItem]
    var onError: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var newTitle = ""
    @State private var editingItemID: UUID?
    @State private var editingTitle = ""
    @State private var isReordering = false
    @FocusState private var isNewItemFocused: Bool

    private var progress: ChecklistProgress {
        ChecklistProgress.from(completedFlags: items.map(\.isCompleted))
    }

    private var orderedItems: [ChecklistItem] {
        items.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.createdAt < $1.createdAt
        }
    }

    var body: some View {
        Section {
            ChecklistProgressHeader(progress: progress)

            if orderedItems.isEmpty, newTitle.isEmpty {
                Text(ChecklistStrings.noItems)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            ForEach(orderedItems, id: \.id) { item in
                checklistRow(item)
            }
            .onMove { source, destination in
                reorder(from: source, to: destination)
            }

            HStack(spacing: NexusSpacing.sm) {
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 28)
                    .accessibilityHidden(true)
                TextField(ChecklistStrings.addItem, text: $newTitle)
                    .focused($isNewItemFocused)
                    .submitLabel(.done)
                    .onSubmit { addItem() }
                if !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(ChecklistStrings.addItem) { addItem() }
                        .fontWeight(.semibold)
                }
            }
            .accessibilityElement(children: .contain)
        } header: {
            HStack {
                Text(ChecklistStrings.checklist)
                Spacer()
                if orderedItems.count > 1 {
                    Button(isReordering ? NexusL10n.tr("common.done") : NexusL10n.tr("checklist.reorder")) {
                        isReordering.toggle()
                    }
                    .font(.caption.weight(.semibold))
                    .accessibilityLabel(isReordering ? NexusL10n.tr("checklist.doneReorder") : NexusL10n.tr("checklist.reorder"))
                }
            }
        }
        .environment(\.editMode, .constant(isReordering ? .active : .inactive))
        .alert(ChecklistStrings.editItem, isPresented: Binding(
            get: { editingItemID != nil },
            set: { if !$0 { editingItemID = nil } }
        )) {
            TextField(ChecklistStrings.editItem, text: $editingTitle)
            Button(NexusL10n.tr("common.save")) { commitEdit() }
            Button(NexusL10n.tr("common.cancel"), role: .cancel) { editingItemID = nil }
        }
    }

    @ViewBuilder
    private func checklistRow(_ item: ChecklistItem) -> some View {
        let index = (orderedItems.firstIndex(where: { $0.id == item.id }) ?? 0) + 1
        let total = orderedItems.count

        HStack(spacing: NexusSpacing.sm) {
            Button {
                toggle(item)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? Color.accentColor : .secondary)
                    .imageScale(.large)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                item.isCompleted ? ChecklistStrings.markIncomplete : ChecklistStrings.markComplete
            )

            Text(item.title)
                .strikethrough(item.isCompleted, color: .secondary)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    editingTitle = item.title
                    editingItemID = item.id
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.title), checklist item, \(item.isCompleted ? "completed" : "incomplete"), \(index) of \(total)"
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(item)
            } label: {
                Label(ChecklistStrings.deleteItem, systemImage: "trash")
            }
            Button(ChecklistStrings.editItem) {
                editingTitle = item.title
                editingItemID = item.id
            }
            .tint(.accentColor)
        }
        .accessibilityAction(named: ChecklistStrings.editItem) {
            editingTitle = item.title
            editingItemID = item.id
        }
        .accessibilityAction(named: ChecklistStrings.deleteItem) {
            delete(item)
        }
    }

    private func toggle(_ item: ChecklistItem) {
        do {
            try ChecklistRepository(context: modelContext).setCompleted(
                itemID: item.id,
                isCompleted: !item.isCompleted
            )
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            onError(UserFacingError.message(for: error))
        }
    }

    private func addItem() {
        let title = ChecklistValidation.normalizeTitle(newTitle)
        guard !title.isEmpty else { return }
        do {
            try ChecklistRepository(context: modelContext).createItem(taskID: taskID, title: title)
            newTitle = ""
            isNewItemFocused = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch RepositoryValidationError.emptyName {
            onError(ChecklistStrings.invalidItem)
        } catch RepositoryValidationError.checklistTitleTooLong {
            onError(ChecklistStrings.titleTooLong)
        } catch {
            onError(UserFacingError.message(for: error))
        }
    }

    private func delete(_ item: ChecklistItem) {
        do {
            try ChecklistRepository(context: modelContext).deleteItem(itemID: item.id)
        } catch {
            onError(UserFacingError.message(for: error))
        }
    }

    private func commitEdit() {
        guard let editingItemID else { return }
        do {
            try ChecklistRepository(context: modelContext).updateItem(
                itemID: editingItemID,
                title: editingTitle
            )
            self.editingItemID = nil
        } catch RepositoryValidationError.emptyName {
            onError(ChecklistStrings.invalidItem)
        } catch RepositoryValidationError.checklistTitleTooLong {
            onError(ChecklistStrings.titleTooLong)
        } catch {
            onError(UserFacingError.message(for: error))
        }
    }

    private func reorder(from source: IndexSet, to destination: Int) {
        guard let from = source.first else { return }
        var ids = orderedItems.map(\.id)
        let movedID = ids[from]
        ids.move(fromOffsets: source, toOffset: destination)
        guard let newIndex = ids.firstIndex(of: movedID) else { return }
        let beforeID = newIndex + 1 < ids.count ? ids[newIndex + 1] : nil
        do {
            _ = try ChecklistRepository(context: modelContext).moveItem(
                itemID: movedID,
                before: beforeID
            )
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            onError(UserFacingError.message(for: error))
        }
    }
}
