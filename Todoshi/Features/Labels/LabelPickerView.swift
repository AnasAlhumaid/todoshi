import SwiftUI
import SwiftData
import NexusCore

/// Multi-select label picker bound to draft label IDs (no immediate persistence).
struct LabelPickerView: View {
    @Binding var selectedIDs: Set<UUID>
    @Environment(\.modelContext) private var modelContext
    @Query private var labels: [LabelTag]
    @State private var query = ""
    @State private var isCreating = false

    private var sorted: [LabelTag] {
        labels.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var filtered: [LabelTag] {
        let q = SearchText.normalizeQuery(query)
        guard !q.isEmpty else { return sorted }
        return sorted.filter { SearchText.matches($0.name, query: q) }
    }

    var body: some View {
        List {
            if sorted.isEmpty {
                ContentUnavailableView {
                    Label(LabelStrings.noLabels, systemImage: "tag")
                } description: {
                    Text(NexusL10n.tr("label.pickerEmpty"))
                } actions: {
                    Button(LabelStrings.createNewLabel) {
                        isCreating = true
                    }
                }
            } else if filtered.isEmpty {
                ContentUnavailableView(LabelStrings.noMatches, systemImage: "magnifyingglass")
            } else {
                ForEach(filtered, id: \.id) { label in
                    Button {
                        toggle(label.id)
                    } label: {
                        HStack(spacing: NexusSpacing.sm) {
                            Image(systemName: selectedIDs.contains(label.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIDs.contains(label.id) ? Color.accentColor : Color.secondary)
                            Circle()
                                .fill(NexusColor.from(hex: label.colorHex))
                                .frame(width: 12, height: 12)
                            Text(label.name)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .accessibilityLabel(label.name)
                    .accessibilityValue(selectedIDs.contains(label.id) ? NexusL10n.tr("common.selected") : NexusL10n.tr("common.notSelected"))
                    .accessibilityAddTraits(selectedIDs.contains(label.id) ? .isSelected : [])
                }
            }
        }
        .searchable(text: $query, prompt: Text(NexusL10n.tr("label.searchPrompt")))
        .navigationTitle(LabelStrings.selectLabels)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(LabelStrings.createNewLabel)
            }
        }
        .sheet(isPresented: $isCreating) {
            NavigationStack {
                LabelFormView(context: modelContext)
            }
        }
        .onChange(of: labels.map(\.id)) { _, ids in
            selectedIDs = selectedIDs.intersection(Set(ids))
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
}
