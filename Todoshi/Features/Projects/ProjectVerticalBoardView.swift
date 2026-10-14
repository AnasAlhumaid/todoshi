import SwiftUI
import TodoshiCore

struct ProjectVerticalBoardView: View {
    let snapshot: ProjectBoardSnapshot
    let columns: [ProjectColumn]
    let canEditColumns: Bool
    let onAddTask: (ProjectColumn) -> Void
    let onEditTask: (UUID) -> Void
    let onDeleteTask: (UUID) -> Void
    let onMoveToColumn: (UUID, ProjectColumn) -> Void
    let onEditColumns: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedColumnID: UUID?
    @State private var showsAllDone = false

    private var selectedColumn: ProjectColumn? {
        columns.first { $0.id == selectedColumnID } ?? columns.first
    }

    /// Root tasks grouped by the column they resolve to.
    private var tasksByColumn: [UUID: [HomeTaskSummary]] {
        var result: [UUID: [HomeTaskSummary]] = [:]
        for section in snapshot.sections {
            for task in section.tasks {
                guard let column = ProjectColumnsPolicy.column(
                    forColumnID: task.columnID,
                    status: task.status,
                    in: columns
                ) else { continue }
                result[column.id, default: []].append(task)
            }
        }
        return result
    }

    private func visibleTasks(in column: ProjectColumn, from grouped: [UUID: [HomeTaskSummary]]) -> [HomeTaskSummary] {
        let all = grouped[column.id] ?? []
        guard column.kind == .done, !showsAllDone else { return all }
        return Array(all.prefix(ProjectBoardSnapshot.donePreviewLimit))
    }

    var body: some View {
        let grouped = tasksByColumn
        VStack(spacing: 0) {
            if let column = selectedColumn {
                let shown = visibleTasks(in: column, from: grouped)
                ScrollView {
                    LazyVStack(spacing: TodoshiSpacing.sm) {
                        columnPicker(grouped)
                            .padding(.horizontal, -TodoshiSpacing.md)
                            .padding(.bottom, TodoshiSpacing.xxs)
                        if shown.isEmpty {
                            Text(TodoshiL10n.tr("board.emptyLane"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, TodoshiSpacing.lg)
                        }

                        ForEach(shown) { task in
                            ProjectBoardTaskCardView(
                                task: task,
                                column: column,
                                columns: columns,
                                onEdit: { onEditTask(task.id) },
                                onDelete: { onDeleteTask(task.id) },
                                onMoveToColumn: { onMoveToColumn(task.id, $0) }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }

                        if column.kind == .done, !showsAllDone,
                           (grouped[column.id]?.count ?? 0) > ProjectBoardSnapshot.donePreviewLimit {
                            Button(TodoshiL10n.tr("common.showAll")) { showsAllDone = true }
                                .font(.subheadline)
                        }

                        addTaskRow(column)
                    }
                    .padding(.horizontal, TodoshiSpacing.md)
                    .padding(.bottom, TodoshiBrand.tabBarScrollInset)
                    .animation(reduceMotion ? nil : .snappy, value: shown.map(\.id))
                }
            }
        }
        .padding(.top, TodoshiSpacing.xs)
        .background(TodoshiBrand.groupedBackground)
    }

    // MARK: Column picker

    private func columnPicker(_ grouped: [UUID: [HomeTaskSummary]]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TodoshiSpacing.xs) {
                    ForEach(columns) { column in
                        columnChip(column, count: grouped[column.id]?.count ?? 0)
                            .id(column.id)
                    }
                    if canEditColumns {
                        Button(action: onEditColumns) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TodoshiBrand.accent)
                                .frame(width: 40, height: 36)
                                .background(TodoshiBrand.cardBackground, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(TodoshiL10n.tr("columns.edit"))
                    }
                }
                .padding(.horizontal, TodoshiSpacing.md)
            }
            .onAppear {
                // Start on the selected (first) column; RTL horizontal scroll views otherwise open at the far end.
                if let id = selectedColumn?.id { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: selectedColumnID) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func columnChip(_ column: ProjectColumn, count: Int) -> some View {
        let isSelected = column.id == selectedColumn?.id
        let tint = TodoshiColor.from(hex: column.colorHex)
        return Button {
            withAnimation(reduceMotion ? nil : .snappy) { selectedColumnID = column.id }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(column.name)
                    .lineLimit(1)
                Text(count, format: .number)
                    .foregroundStyle(isSelected ? tint : .secondary)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, TodoshiSpacing.sm + 2)
            .frame(minHeight: 36)
            .background {
                Capsule()
                    .fill(isSelected ? TodoshiBrand.cardBackground : Color.primary.opacity(0.05))
                    .shadow(color: isSelected ? .black.opacity(0.06) : .clear, radius: 3, y: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func addTaskRow(_ column: ProjectColumn) -> some View {
        Button {
            onAddTask(column)
        } label: {
            HStack(spacing: TodoshiSpacing.xs) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TodoshiBrand.accent)
                Text(TodoshiL10n.format("board.addTo", column.name))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .padding(.horizontal, TodoshiSpacing.md)
            .frame(minHeight: 52)
            .background(TodoshiBrand.cardBackground, in: RoundedRectangle(cornerRadius: TodoshiRadius.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Column editor

/// Rename, recolor, reorder, add and remove a personal project's board columns.
struct ProjectColumnsEditorView: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var columns: [ProjectColumn]
    /// Removed column ID → same-kind column that inherits its tasks.
    @State private var reassignments: [UUID: UUID] = [:]
    @State private var errorMessage: String?

    private static let palette = ["#5248D9", "#3E8BEB", "#1D9E75", "#30A46C", "#E8920C", "#E5484D", "#E5487D", "#8E5BD9", "#7A7889"]

    init(project: Project) {
        self.project = project
        _columns = State(initialValue: ProjectColumnsPolicy.columns(for: project))
    }

    var body: some View {
        List {
            Section {
                ForEach($columns) { $column in
                    columnRow($column)
                }
                .onMove { columns.move(fromOffsets: $0, toOffset: $1) }
                .onDelete(perform: delete)
            } footer: {
                Text(TodoshiL10n.tr("columns.kindFooter"))
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        // No forced edit mode: it swallows taps on the name field and color swatches.
        // Rows still reorder with long-press drag and delete with a swipe.
        .safeAreaInset(edge: .bottom) {
            Button {
                addColumn()
            } label: {
                Label(TodoshiL10n.tr("columns.add"), systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(TodoshiBrand.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(columns.count >= ProjectColumnsPolicy.maximumColumns)
            .padding(.horizontal, TodoshiSpacing.md)
            .padding(.bottom, TodoshiSpacing.xs)
        }
        .navigationTitle(TodoshiL10n.tr("columns.edit"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(TodoshiL10n.tr("common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(TodoshiL10n.tr("common.save")) { save() }
                    .fontWeight(.semibold)
            }
        }
    }

    private func columnRow(_ column: Binding<ProjectColumn>) -> some View {
        VStack(alignment: .leading, spacing: TodoshiSpacing.xs) {
            HStack(spacing: TodoshiSpacing.xs) {
                Circle()
                    .fill(TodoshiColor.from(hex: column.wrappedValue.colorHex))
                    .frame(width: 12, height: 12)
                TextField(TodoshiL10n.tr("columns.namePlaceholder"), text: column.name)
                    .font(.body.weight(.medium))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.palette, id: \.self) { hex in
                        Button {
                            column.wrappedValue.colorHex = hex
                        } label: {
                            Circle()
                                .fill(TodoshiColor.from(hex: hex))
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if column.wrappedValue.colorHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Picker(TodoshiL10n.tr("columns.kindLabel"), selection: column.kind) {
                ForEach(ProjectColumnKind.allCases) { kind in
                    Text(kind.displayName()).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, TodoshiSpacing.xxs)
    }

    private func addColumn() {
        let hex = Self.palette[columns.count % Self.palette.count]
        columns.append(ProjectColumn(name: TodoshiL10n.tr("columns.newColumn"), colorHex: hex, kind: .doing))
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let removed = columns[index]
            let remaining = columns.enumerated()
                .filter { !offsets.contains($0.offset) }
                .map(\.element)
            guard let heir = remaining.first(where: { $0.kind == removed.kind }) else {
                errorMessage = TodoshiL10n.format("columns.error.missingKind", removed.kind.displayName())
                return
            }
            reassignments[removed.id] = heir.id
            // Chains: anything that pointed at the removed column now points at its heir.
            for (key, value) in reassignments where value == removed.id {
                reassignments[key] = heir.id
            }
        }
        errorMessage = nil
        columns.remove(atOffsets: offsets)
    }

    private func save() {
        let trimmed = columns.map { column -> ProjectColumn in
            var copy = column
            copy.name = column.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return copy
        }
        do {
            try ProjectRepository(context: modelContext).updateColumns(
                trimmed,
                for: project,
                reassignments: reassignments
            )
            dismiss()
        } catch let error as ProjectColumnsValidationError {
            switch error {
            case .emptyName:
                errorMessage = TodoshiL10n.tr("columns.error.emptyName")
            case .missingKind(let kind):
                errorMessage = TodoshiL10n.format("columns.error.missingKind", kind.displayName())
            case .tooMany:
                errorMessage = TodoshiL10n.format("columns.error.tooMany", ProjectColumnsPolicy.maximumColumns)
            }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
