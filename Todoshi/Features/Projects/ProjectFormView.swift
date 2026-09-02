import SwiftUI
import SwiftData
import NexusCore

struct ProjectFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ProjectFormViewModel

    init(context: ModelContext, projectID: UUID? = nil) {
        _viewModel = State(initialValue: ProjectFormViewModel(context: context, projectID: projectID))
    }

    var body: some View {
        Form {
            Section(NexusL10n.tr("form.details")) {
                TextField(NexusL10n.tr("common.name"), text: $viewModel.draft.name)
                    .textInputAutocapitalization(.words)
                TextField(NexusL10n.tr("common.description"), text: $viewModel.draft.projectDescription, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section(NexusL10n.tr("common.icon")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: NexusSpacing.sm) {
                    ForEach(ProjectIconCatalog.symbols, id: \.self) { symbol in
                        Button {
                            viewModel.draft.icon = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(
                                    viewModel.draft.icon == symbol
                                    ? NexusColor.from(hex: viewModel.draft.colorHex).opacity(0.2)
                                    : Color.secondary.opacity(0.12)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: NexusRadius.sm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                        .accessibilityAddTraits(viewModel.draft.icon == symbol ? .isSelected : [])
                    }
                }
            }

            Section(NexusL10n.tr("common.color")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: NexusSpacing.sm) {
                    ForEach(ProjectColorCatalog.swatches) { swatch in
                        Button {
                            viewModel.draft.colorHex = swatch.hex
                        } label: {
                            Circle()
                                .fill(NexusColor.from(hex: swatch.hex))
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
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NexusL10n.tr("common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(NexusL10n.tr("common.save")) {
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
