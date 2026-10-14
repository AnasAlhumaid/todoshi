import SwiftUI
import TodoshiCore

struct PrivacyInfoView: View {
    var body: some View {
        List {
            Section {
                Text(TodoshiL10n.tr("privacy.intro"))
                    .font(.body)
            }

            Section(TodoshiL10n.tr("privacy.sectionDevice")) {
                privacyRow(TodoshiL10n.tr("privacy.device.tasks"))
                privacyRow(TodoshiL10n.tr("privacy.device.files"))
                privacyRow(TodoshiL10n.tr("privacy.device.notifications"))
                privacyRow(TodoshiL10n.tr("privacy.device.widgets"))
            }

            Section(TodoshiL10n.tr("privacy.sectionNot")) {
                privacyRow(TodoshiL10n.tr("privacy.not.account"))
                privacyRow(TodoshiL10n.tr("privacy.not.cloud"))
                privacyRow(TodoshiL10n.tr("privacy.not.analytics"))
                privacyRow(TodoshiL10n.tr("privacy.not.ads"))
            }

            Section(TodoshiL10n.tr("privacy.sectionExternal")) {
                Text(TodoshiL10n.tr("privacy.external"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section(TodoshiL10n.tr("privacy.sectionDelete")) {
                Text(TodoshiL10n.tr("privacy.deletion"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(TodoshiL10n.tr("privacy.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacyRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle")
            .font(.subheadline)
    }
}
