import SwiftUI
import NexusCore

struct SettingsView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nexus")
                        .font(.headline)
                    Text(NexusL10n.tr("settings.tagline"))
                        .font(NexusTypography.metadata)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .listRowBackground(Color.clear)
            }

            Section(NexusL10n.tr("settings.organization")) {
                NavigationLink(value: AppRoute.labels) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LabelStrings.labels)
                            Text(NexusL10n.tr("settings.labelsDescription"))
                                .font(NexusTypography.metadata)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "tag")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section(NexusL10n.tr("settings.notifications")) {
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label(NexusL10n.tr("settings.notifications"), systemImage: "bell")
                }
            }

            Section(NexusL10n.tr("settings.privacy")) {
                NavigationLink {
                    PrivacyInfoView()
                } label: {
                    Label(NexusL10n.tr("settings.privacyData"), systemImage: "hand.raised")
                }
            }

            Section(NexusL10n.tr("settings.about")) {
                LabeledContent(NexusL10n.tr("common.version"), value: AppVersionInfo.displayVersion)
                LabeledContent(NexusL10n.tr("common.platform"), value: "iOS")
                Text(NexusL10n.tr("settings.localFirst"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            #if DEBUG
            Section(NexusL10n.tr("settings.debugSection")) {
                Text(NexusL10n.tr("settings.debugReset"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent(
                    NexusL10n.tr("settings.destructiveReset"),
                    value: StoreResetPolicy.allowsDestructiveAppGroupReset ? NexusL10n.tr("settings.allowed") : NexusL10n.tr("settings.disabled")
                )
            }
            #endif
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NexusL10n.tr("settings.title"))
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
