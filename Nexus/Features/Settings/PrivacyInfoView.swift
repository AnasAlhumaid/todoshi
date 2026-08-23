import SwiftUI
import NexusCore

struct PrivacyInfoView: View {
    var body: some View {
        List {
            Section {
                Text(NexusL10n.tr("privacy.intro"))
                    .font(.body)
            }

            Section(NexusL10n.tr("privacy.sectionDevice")) {
                privacyRow(NexusL10n.tr("privacy.device.tasks"))
                privacyRow(NexusL10n.tr("privacy.device.files"))
                privacyRow(NexusL10n.tr("privacy.device.notifications"))
                privacyRow(NexusL10n.tr("privacy.device.widgets"))
            }

            Section(NexusL10n.tr("privacy.sectionNot")) {
                privacyRow(NexusL10n.tr("privacy.not.account"))
                privacyRow(NexusL10n.tr("privacy.not.cloud"))
                privacyRow(NexusL10n.tr("privacy.not.analytics"))
                privacyRow(NexusL10n.tr("privacy.not.ads"))
            }

            Section(NexusL10n.tr("privacy.sectionExternal")) {
                Text(NexusL10n.tr("privacy.external"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section(NexusL10n.tr("privacy.sectionDelete")) {
                Text(NexusL10n.tr("privacy.deletion"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(NexusL10n.tr("privacy.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacyRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle")
            .font(.subheadline)
    }
}
