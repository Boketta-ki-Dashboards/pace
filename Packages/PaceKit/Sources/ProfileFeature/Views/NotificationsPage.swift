import DesignSystem
import PaceCore
import SwiftUI
import UIKit

/// Mitteilungen: Erlaubnis von iOS und die lokale Erinnerung an das Tagesziel. Push-Mitteilungen werden ehrlich als
/// „folgt“ erklärt, nicht als Schalter angeboten.
struct NotificationsPage: View {
    let viewModel: NotificationSettingsViewModel
    let backTitle: String

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ProfileSubpage {
            NotificationsPageContent(viewModel: viewModel, backTitle: backTitle) {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
        }
        .task { [viewModel] in await viewModel.refreshAuthorization() }
        // Nach der Rückkehr aus den iOS-Einstellungen den Status neu lesen.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.refreshAuthorization() }
            }
        }
    }
}

struct NotificationsPageContent: View {
    let viewModel: NotificationSettingsViewModel
    let backTitle: String
    var onOpenSystemSettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: ProfileRoute.notifications.title)
                .padding(.bottom, PaceSpacing.xs)

            if viewModel.isAvailable {
                permissionCard
                reminderCard
            } else {
                PaceCard {
                    ProfileNoteRow(systemImage: "bell.slash", text: PaceLocalization.text(
                        de: "Mitteilungen sind in dieser Umgebung nicht verfügbar.",
                        en: "Notifications aren't available in this environment.",
                        ru: "Уведомления недоступны в этой среде."
                    ))
                }
            }

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceCardHeader(PaceLocalization.text(de: "Weitere Mitteilungen", en: "More notifications", ru: "Другие уведомления"))
                    ProfileNoteRow(systemImage: "bell.badge", text: viewModel.pushNotice)
                }
            }
        }
    }

    private var permissionCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                HStack(alignment: .top, spacing: PaceSpacing.s) {
                    ProfileRowIcon(
                        systemImage: viewModel.authorization == .denied ? "bell.slash" : "bell.badge",
                        tint: viewModel.authorization == .denied ? PaceColor.textSecondary : PaceColor.accent
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.statusTitle)
                            .font(PaceFont.headline)
                            .foregroundStyle(PaceColor.textPrimary)
                        Text(viewModel.statusMessage)
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                switch viewModel.authorization {
                case .notDetermined?:
                    Button(PaceLocalization.text(de: "Mitteilungen erlauben", en: "Allow notifications", ru: "Разрешить уведомления")) {
                        Task { await viewModel.requestAuthorization() }
                    }
                    .buttonStyle(.pacePrimary)
                case .denied?:
                    Button(PaceLocalization.text(de: "iOS-Einstellungen öffnen", en: "Open iOS Settings", ru: "Открыть настройки iOS")) {
                        onOpenSystemSettings()
                    }
                    .buttonStyle(.paceSecondary)
                case .authorized?, nil:
                    EmptyView()
                }
            }
        }
    }

    private var reminderCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(PaceLocalization.text(
                    de: "Erinnerung an dein Tagesziel",
                    en: "Daily goal reminder",
                    ru: "Напоминание о дневной цели"
                ))
                ProfileToggleTile(
                    title: PaceLocalization.text(de: "Täglich erinnern", en: "Remind me daily", ru: "Напоминать ежедневно"),
                    isOn: viewModel.reminder.isEnabled,
                    isHighlighted: viewModel.reminder.isEnabled,
                    isDisabled: viewModel.isUpdating
                ) { enabled in
                    Task { await viewModel.setReminderEnabled(enabled) }
                }
                if viewModel.reminder.isEnabled {
                    PaceTile {
                        DatePicker(
                            selection: Binding(
                                get: { [date = viewModel.reminderDate] in date },
                                set: { [viewModel] date in Task { await viewModel.setReminderTime(date) } }
                            ),
                            displayedComponents: .hourAndMinute
                        ) {
                            Text(PaceLocalization.text(de: "Uhrzeit", en: "Time", ru: "Время"))
                                .font(PaceFont.headline)
                                .foregroundStyle(PaceColor.textPrimary)
                        }
                        .tint(PaceColor.accentStrong)
                        .padding(.vertical, PaceSpacing.xxs)
                    }
                }
                if let message = viewModel.message {
                    ProfileFootnote(text: message, isError: true)
                } else if viewModel.reminderBlockedByPermission {
                    ProfileFootnote(text: NotificationSettingsViewModel.deniedMessage, isError: true)
                }
                ProfileFootnote(text: viewModel.reminderExplanation)
            }
        }
    }
}
