import SwiftUI
import NexusCore

/// Inline checklist draft editor for Task Form (no SwiftData mutations until Save).
struct TaskFormChecklistSection: View {
    @Binding var items: [ChecklistItemDraft]
    var focusedID: Binding<UUID?>
    var onAdd: () -> Void
    var onDelete: (UUID) -> Void
    var onMove: (IndexSet, Int) -> Void

    @FocusState private var localFocus: UUID?

    var body: some View {
        Section {
            if items.isEmpty {
                Text(ChecklistStrings.noItems)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach($items) { $item in
                    HStack(spacing: NexusSpacing.sm) {
                        Button {
                            item.isCompleted.toggle()
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

                        TextField(ChecklistStrings.addItem, text: $item.title)
                            .focused($localFocus, equals: item.id)
                            .strikethrough(item.isCompleted, color: .secondary)
                            .foregroundStyle(item.isCompleted ? .secondary : .primary)
                            .submitLabel(.next)
                            .onSubmit {
                                onAdd()
                            }
                            .accessibilityLabel(item.title.isEmpty ? ChecklistStrings.addItem : item.title)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            onDelete(item.id)
                        } label: {
                            Label(ChecklistStrings.deleteItem, systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: onMove)
            }

            Button {
                onAdd()
            } label: {
                Label(ChecklistStrings.addItem, systemImage: "plus.circle")
            }
            .accessibilityLabel(ChecklistStrings.addItem)
        } header: {
            Text(ChecklistStrings.checklist)
        } footer: {
            Text(NexusL10n.tr("checklist.formHint"))
                .font(.footnote)
        }
        .onChange(of: focusedID.wrappedValue) { _, newValue in
            localFocus = newValue
        }
        .onChange(of: localFocus) { _, newValue in
            focusedID.wrappedValue = newValue
        }
    }
}
