import DesignSystem
import PaceCore
import SwiftUI
import UIKit

/// Mitteilungen: Erlaubnis von iOS, die lokalen Erinnerungen an das Tagesziel und Hinweise auf neue Chatnachrichten
/// (solange Pace geöffnet ist). Push-Mitteilungen bei geschlossener App werden ehrlich als nicht eingerichtet erklärt,
/// nicht als Schalter angeboten.
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
                chatCard
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
                    de: "Tagesziel-Erinnerungen",
                    en: "Daily goal reminders",
                    ru: "Напоминания о дневной цели"
                ))
                ProfileToggleTile(
                    title: PaceLocalization.text(de: "Erinnerungen", en: "Reminders", ru: "Напоминания"),
                    isOn: viewModel.reminder.isEnabled,
                    isHighlighted: viewModel.reminder.isEnabled,
                    isDisabled: viewModel.isUpdating
                ) { enabled in
                    Task { await viewModel.setReminderEnabled(enabled) }
                }
                if viewModel.reminder.isEnabled {
                    // Stabile Zeilen (Position statt Uhrzeit), damit die Zeitauswahl beim Ändern nicht neu aufgebaut wird.
                    ForEach(Array(viewModel.reminder.times.enumerated()), id: \.offset) { _, time in
                        reminderTimeRow(time)
                    }
                    if viewModel.reminder.canAddTime {
                        Button {
                            Task { await viewModel.addReminderTime() }
                        } label: {
                            Label(
                                PaceLocalization.text(de: "Uhrzeit hinzufügen", en: "Add time", ru: "Добавить время"),
                                systemImage: "plus"
                            )
                            .font(.system(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.paceSoft)
                    } else {
                        ProfileFootnote(text: PaceLocalization.text(
                            de: "Höchstens \(StreakReminderSettings.maximumTimes) Erinnerungen am Tag.",
                            en: "At most \(StreakReminderSettings.maximumTimes) reminders a day.",
                            ru: "Не больше \(StreakReminderSettings.maximumTimes) напоминаний в день."
                        ))
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

    private var chatCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(PaceLocalization.text(de: "Chatnachrichten", en: "Chat messages", ru: "Сообщения в чатах"))
                ProfileToggleTile(
                    title: PaceLocalization.text(
                        de: "Hinweis bei neuen Nachrichten", en: "Alert for new messages", ru: "Сообщать о новых сообщениях"
                    ),
                    isOn: viewModel.chatMessageHints,
                    isHighlighted: viewModel.chatMessageHints,
                    isDisabled: viewModel.isUpdating
                ) { enabled in
                    Task { await viewModel.setChatMessageHints(enabled) }
                }
                ProfileFootnote(text: viewModel.chatHintExplanation)
            }
        }
    }

    /// Eine Uhrzeit: Zeitauswahl und – wenn es mehr als eine gibt – Entfernen.
    private func reminderTimeRow(_ time: ReminderTime) -> some View {
        PaceTile {
            HStack(spacing: PaceSpacing.s) {
                Image(systemName: "bell")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PaceColor.accent)
                    .accessibilityHidden(true)
                DatePicker(
                    selection: Binding(
                        get: { [date = viewModel.date(for: time)] in date },
                        set: { [viewModel] date in Task { await viewModel.updateReminderTime(time, to: date) } }
                    ),
                    displayedComponents: .hourAndMinute
                ) {
                    Text(PaceLocalization.text(de: "Uhrzeit", en: "Time", ru: "Время"))
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                }
                .tint(PaceColor.accentStrong)
                if viewModel.reminder.times.count > 1 {
                    Button {
                        Task { await viewModel.removeReminderTime(time) }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(PaceColor.danger)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(PaceLocalization.text(
                        de: "Erinnerung um \(viewModel.timeText(time)) entfernen",
                        en: "Remove reminder at \(viewModel.timeText(time))",
                        ru: "Удалить напоминание в \(viewModel.timeText(time))"
                    ))
                }
            }
            .padding(.vertical, PaceSpacing.xxs)
        }
    }
}
