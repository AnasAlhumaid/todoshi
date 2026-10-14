import SwiftUI
import TodoshiCore

struct SettingsView: View {
    @Environment(AppLanguageController.self) private var appLanguage
    @Environment(AuthSessionController.self) private var authSession

    var body: some View {
        List {
            Section {
                HStack(spacing: TodoshiSpacing.md) {
                    TodoshiLogoMark(size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        TodoshiWordmark(size: .headline.weight(.bold))
                        Text(TodoshiL10n.tr("settings.tagline"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .listRowBackground(Color.clear)
            }

            AccountView()

            Section(AppLanguagePresentation.sectionTitle) {
                Picker(selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(AppLanguagePresentation.title(for: language)).tag(language)
                    }
                } label: {
                    Text(AppLanguagePresentation.rowLabel)
                }
                .pickerStyle(.menu)
                .accessibilityLabel(AppLanguagePresentation.sectionTitle)
                .accessibilityValue(AppLanguagePresentation.title(for: appLanguage.preference))
            }

            Section(TodoshiL10n.tr("settings.organization")) {
                NavigationLink(value: AppRoute.labels) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LabelStrings.labels)
                            Text(TodoshiL10n.tr("settings.labelsDescription"))
                                .font(TodoshiTypography.metadata)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "tag")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section(TodoshiL10n.tr("settings.notifications")) {
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label(TodoshiL10n.tr("settings.notifications"), systemImage: "bell")
                }
            }

            Section(TodoshiL10n.tr("settings.privacy")) {
                NavigationLink {
                    PrivacyInfoView()
                } label: {
                    Label(TodoshiL10n.tr("settings.privacyData"), systemImage: "hand.raised")
                }
            }

            Section(TodoshiL10n.tr("settings.about")) {
                LabeledContent(TodoshiL10n.tr("common.version"), value: AppVersionInfo.displayVersion)
                LabeledContent(TodoshiL10n.tr("common.platform"), value: "iOS")
                Text(TodoshiL10n.tr("settings.localFirst"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            #if DEBUG
            Section(TodoshiL10n.tr("settings.debugSection")) {
                Text(TodoshiL10n.tr("settings.debugReset"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent(
                    TodoshiL10n.tr("settings.destructiveReset"),
                    value: StoreResetPolicy.allowsDestructiveAppGroupReset ? TodoshiL10n.tr("settings.allowed") : TodoshiL10n.tr("settings.disabled")
                )
                Text("authInstance=\(String(describing: authSession.instanceID))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("settingsAuthInstanceLabel")
            }
            #endif
        }
        .listStyle(.insetGrouped)
        .navigationTitle(TodoshiL10n.tr("settings.title"))
        .onAppear {
            #if DEBUG
            let label: String
            switch authSession.state {
            case .loading: label = "loading"
            case .signedOut: label = "signedOut"
            case .signedIn: label = "signedIn"
            }
            TodoshiDiagnostics.note("[Settings] authInstance=\(authSession.instanceID) state=\(label)")
            #endif
        }
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { appLanguage.preference },
            set: { appLanguage.select($0) }
        )
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppLanguageController())
            .environment(AuthSessionController())
    }
}
