import SwiftUI
import SwiftData
import NexusCore

struct LabelTasksView: View {
    let labelID: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var labels: [LabelTag]
    @State private var includeArchived = false
    @State private var rows: [LabelTaskRow] = []

    init(labelID: UUID) {
        self.labelID = labelID
        let id = labelID
        _labels = Query(filter: #Predicate<LabelTag> { $0.id == id })
    }

    private var label: LabelTag? { labels.first }

    var body: some View {
        Group {
            if let label {
                content(for: label)
            } else {
                ContentUnavailableView(NexusL10n.tr("label.notFound"), systemImage: "tag.slash")
            }
        }
        .onAppear { reload() }
        .onChange(of: includeArchived) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: NexusDataChangeCenter.notification)) { _ in
            reload()
        }
    }

    @ViewBuilder
    private func content(for label: LabelTag) -> some View {
        List {
            Section {
                HStack(spacing: NexusSpacing.sm) {
                    Circle()
                        .fill(NexusColor.from(hex: label.colorHex))
                        .frame(width: 8, height: 8)
                    Text(label.name)
                        .font(.body.weight(.medium))
                    Spacer()
                    Text("\(rows.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(rows.count) tasks")
                }
                Toggle(NexusL10n.tr("search.includeArchived"), isOn: $includeArchived)
            }

            if rows.isEmpty {
                ContentUnavailableView(
                    LabelStrings.noAssignedTasks,
                    systemImage: "checklist",
                    description: Text(NexusL10n.tr("label.assignedEmpty"))
                )
            } else {
                ForEach(rows) { row in
                    NavigationLink(value: AppRoute.task(row.id)) {
                        NexusTaskRow(
                            title: row.title,
                            context: row.projectName,
                            showsProjectGlyph: false,
                            priority: row.priority,
                            status: row.status,
                            showStatus: true,
                            showsLabels: false
                        )
                    }
                }
            }
        }
        .navigationTitle(LabelStrings.assignedTasks)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reload() {
        rows = (try? LabelRepository(context: modelContext)
            .rootTaskRows(for: labelID, includeArchived: includeArchived)) ?? []
    }
}
