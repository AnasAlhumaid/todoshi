import SwiftUI
import SwiftData
import NexusCore

struct LabelFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: LabelFormViewModel

    init(context: ModelContext, labelID: UUID? = nil) {
        _viewModel = State(initialValue: LabelFormViewModel(context: context, labelID: labelID))
    }

    var body: some View {
        Form {
            Section(LabelStrings.name) {
                TextField(LabelStrings.namePlaceholder, text: $viewModel.draft.name)
                    .onChange(of: viewModel.draft.name) { _, _ in
                        viewModel.validateLive()
                    }
                    .accessibilityLabel(LabelStrings.name)
            }

            Section(NexusL10n.tr("common.color")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                    ForEach(LabelColorCatalog.swatches) { swatch in
                        Button {
                            viewModel.draft.colorHex = swatch.hex
                            viewModel.validateLive()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(NexusColor.from(hex: swatch.hex))
                                    .frame(width: 36, height: 36)
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
                            viewModel.draft.colorHex.uppercased() == swatch.hex.uppercased()
                                ? .isSelected
                                : []
                        )
                    }
                }
                .padding(.vertical, 4)
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
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
                    if viewModel.save() { dismiss() }
                }
                .disabled(!viewModel.canSave)
                .fontWeight(.semibold)
            }
        }
        .onAppear { viewModel.validateLive() }
    }
}
