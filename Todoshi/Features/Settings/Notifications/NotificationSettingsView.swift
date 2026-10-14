import SwiftUI
import SwiftData
import TodoshiCore

struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = NotificationSettingsViewModel()

    var body: some View {
        List {
            Section {
                LabeledContent(TodoshiL10n.tr("notification.status"), value: viewModel.authorizationLabel)
                if viewModel.canRequestAuthorization {
                    Button(NotificationStrings.enableTitle) {
                        viewModel.showPermissionExplainer = true
                    }
                }
                if viewModel.isDenied {
                    Text(NotificationStrings.deniedMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(NotificationStrings.openSettings) {
                        viewModel.openSystemSettings()
                    }
                }
            } header: {
                Text(NotificationStrings.authorization)
            } footer: {
                Text(NotificationStrings.privacyNote)
            }

            Section(NotificationStrings.dailySummary) {
                Toggle(TodoshiL10n.tr("notification.enableDaily"), isOn: $viewModel.preferences.isEnabled)
                    .disabled(!viewModel.isAuthorized)
                    .onChange(of: viewModel.preferences.isEnabled) { _, _ in
                        Task { await viewModel.savePreferences(context: modelContext) }
                    }

                if viewModel.preferences.isEnabled {
                    DatePicker(
                        NotificationStrings.dailySummaryTime,
                        selection: summaryTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!viewModel.isAuthorized)
                    .onChange(of: viewModel.preferences.hour) { _, _ in
                        Task { await viewModel.savePreferences(context: modelContext) }
                    }
                    .onChange(of: viewModel.preferences.minute) { _, _ in
                        Task { await viewModel.savePreferences(context: modelContext) }
                    }
                }
            }

            Section(TodoshiL10n.tr("notification.reminders")) {
                LabeledContent(NotificationStrings.pendingCount) {
                    Text("\(viewModel.pendingReminderCount)")
                        .monospacedDigit()
                }
                Button(NotificationStrings.repair) {
                    Task { await viewModel.repair(context: modelContext) }
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(TodoshiL10n.tr("settings.notifications"))
        .task {
            await viewModel.refreshStatus()
        }
        .alert(NotificationStrings.enableTitle, isPresented: $viewModel.showPermissionExplainer) {
            Button(NotificationStrings.notNow, role: .cancel) {}
            Button(NotificationStrings.allow) {
                Task { await viewModel.requestAuthorization(context: modelContext) }
            }
        } message: {
            Text(NotificationStrings.enableMessage)
        }
    }

    private var summaryTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = viewModel.preferences.hour
                components.minute = viewModel.preferences.minute
                return Calendar.current.date(from: components) ?? .now
            },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                viewModel.preferences.hour = comps.hour ?? DailySummaryPreferences.defaultHour
                viewModel.preferences.minute = comps.minute ?? DailySummaryPreferences.defaultMinute
            }
        )
    }
}
