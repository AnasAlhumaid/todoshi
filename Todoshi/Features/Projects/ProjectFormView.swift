import SwiftUI
import SwiftData
import TodoshiCore

struct ProjectFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ProjectFormViewModel

    init(context: ModelContext, projectID: UUID? = nil) {
        _viewModel = State(initialValue: ProjectFormViewModel(context: context, projectID: projectID))
    }

    var body: some View {
        Group {
            if viewModel.step == .chooseType {
                typeSelection
            } else {
                detailsForm
            }
        }
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(TodoshiL10n.tr("common.cancel")) { dismiss() }
            }
            if viewModel.step == .details, !viewModel.isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button(TodoshiL10n.tr("common.back")) {
                        viewModel.goBackToTypeSelection()
                    }
                }
            }
            if viewModel.step == .details {
                ToolbarItem(placement: .confirmationAction) {
                    Button(TodoshiL10n.tr("common.save")) {
                        if viewModel.save() {
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.canSave)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var typeSelection: some View {
        ScrollView {
            VStack(spacing: TodoshiSpacing.md) {
                ForEach(ProjectType.allCases) { type in
                    Button {
                        viewModel.selectType(type)
                    } label: {
                        HStack(alignment: .top, spacing: TodoshiSpacing.md) {
                            Image(systemName: ProjectTypeCapabilities.defaultIcon(for: type))
                                .font(.title2)
                                .foregroundStyle(.primary)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ProjectTerminologyPolicy.typeTitle(type))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(ProjectTerminologyPolicy.typeSubtitle(type))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(TodoshiSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: TodoshiRadius.md, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(ProjectTerminologyPolicy.typeTitle(type)). \(ProjectTerminologyPolicy.typeSubtitle(type))"
                    )
                }
            }
            .padding(TodoshiSpacing.md)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var detailsForm: some View {
        Form {
            if !viewModel.isEditing {
                Section {
                    Label(
                        ProjectTerminologyPolicy.typeTitle(viewModel.draft.projectType),
                        systemImage: ProjectTypeCapabilities.defaultIcon(for: viewModel.draft.projectType)
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section(TodoshiL10n.tr("form.details")) {
                TextField(TodoshiL10n.tr("common.name"), text: $viewModel.draft.name)
                    .textInputAutocapitalization(.words)
                TextField(TodoshiL10n.tr("common.description"), text: $viewModel.draft.projectDescription, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section(TodoshiL10n.tr("common.icon")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: TodoshiSpacing.sm) {
                    ForEach(ProjectIconCatalog.symbols, id: \.self) { symbol in
                        Button {
                            viewModel.draft.icon = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(
                                    viewModel.draft.icon == symbol
                                    ? TodoshiColor.from(hex: viewModel.draft.colorHex).opacity(0.2)
                                    : Color.secondary.opacity(0.12)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: TodoshiRadius.sm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                        .accessibilityAddTraits(viewModel.draft.icon == symbol ? .isSelected : [])
                    }
                }
            }

            Section(TodoshiL10n.tr("common.color")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: TodoshiSpacing.sm) {
                    ForEach(ProjectColorCatalog.swatches) { swatch in
                        Button {
                            viewModel.draft.colorHex = swatch.hex
                        } label: {
                            Circle()
                                .fill(TodoshiColor.from(hex: swatch.hex))
                                .frame(width: 36, height: 36)
                                .overlay {
                                    if viewModel.draft.colorHex.uppercased() == swatch.hex.uppercased() {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(swatch.name)
                        .accessibilityAddTraits(
                            viewModel.draft.colorHex.uppercased() == swatch.hex.uppercased() ? .isSelected : []
                        )
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
    }
}
