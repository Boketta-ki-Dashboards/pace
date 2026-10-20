import Foundation
import Observation
import PaceCore

/// Mitteilungen: Erlaubnis von iOS und die lokale Erinnerung an das Tagesziel.
///
/// Die Erinnerung wird für die nächsten Tage im Voraus geplant (ohne Server). Ist das Ziel heute schon erreicht,
/// beginnt sie morgen – deshalb wird beim Start der App, beim Erreichen des Ziels, bei einer anderen Uhrzeit und beim
/// Sprachwechsel neu geplant. Push-Mitteilungen (Anfragen, Einladungen, Chat) brauchen einen Push-Dienst auf dem
/// Server und werden deshalb nicht als Schalter angeboten.
@MainActor
@Observable
public final class NotificationSettingsViewModel {
    /// Was zuletzt geplant wurde – unveränderte Pläne werden nicht erneut an iOS übergeben.
    struct Plan: Equatable {
        let hour: Int
        let minute: Int
        let skipToday: Bool
        let language: AppLanguage
    }

    /// Erlaubnis von iOS; `nil`, solange sie nicht abgefragt wurde.
    public private(set) var authorization: NotificationAuthorization?
    public private(set) var isUpdating = false
    /// Hinweis nach einer abgelehnten Erlaubnis.
    public private(set) var message: String?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let notifications: (any LocalNotificationScheduling)?
    @ObservationIgnored private let isTodayGoalReached: @MainActor () -> Bool
    @ObservationIgnored private var lastPlan: Plan??

    /// - Parameter isTodayGoalReached: Ob das heutige Tagesziel schon erreicht ist (dann beginnt die Erinnerung morgen).
    public init(
        settings: AppSettings,
        notifications: (any LocalNotificationScheduling)?,
        isTodayGoalReached: @escaping @MainActor () -> Bool = { false }
    ) {
        self.settings = settings
        self.notifications = notifications
        self.isTodayGoalReached = isTodayGoalReached
    }

    /// Ohne angebundene Mitteilungen (z. B. Tests) zeigt die Seite einen ehrlichen Hinweis.
    public var isAvailable: Bool { notifications != nil }

    public var reminder: StreakReminderSettings { settings.streakReminder }

    /// Ob das heutige Ziel erreicht ist – für Auslöser in der Oberfläche (neu planen, sobald es sich ändert).
    public var todayGoalReached: Bool { isTodayGoalReached() }

    /// Uhrzeit der Erinnerung, z. B. `19:00` bzw. `7:00 PM`.
    public var reminderTimeText: String {
        let components = DateComponents(hour: reminder.hour, minute: reminder.minute)
        guard let date = Calendar(identifier: .gregorian).date(from: components) else {
            return String(format: "%02d:%02d", reminder.hour, reminder.minute)
        }
        var style = Date.FormatStyle.pace(Date.FormatStyle(date: .omitted, time: .shortened))
        style.timeZone = Calendar(identifier: .gregorian).timeZone
        return date.formatted(style)
    }

    // MARK: Erlaubnis

    public func refreshAuthorization() async {
        guard let notifications else { return }
        authorization = await notifications.authorization()
        if authorization == .authorized { message = nil }
    }

    /// Fragt iOS nach der Erlaubnis (nur möglich, solange noch nicht gefragt wurde).
    @discardableResult
    public func requestAuthorization() async -> Bool {
        guard let notifications else { return false }
        let granted = await notifications.requestAuthorization()
        authorization = await notifications.authorization()
        message = granted ? nil : Self.deniedMessage
        return granted
    }

    public var statusTitle: String {
        switch authorization {
        case .authorized:
            PaceLocalization.text(de: "Mitteilungen erlaubt", en: "Notifications allowed", ru: "Уведомления разрешены")
        case .denied:
            PaceLocalization.text(de: "Mitteilungen ausgeschaltet", en: "Notifications turned off", ru: "Уведомления выключены")
        case .notDetermined:
            PaceLocalization.text(de: "Noch nicht erlaubt", en: "Not allowed yet", ru: "Ещё не разрешены")
        case nil:
            PaceLocalization.text(de: "Wird geprüft …", en: "Checking …", ru: "Проверяем …")
        }
    }

    public var statusMessage: String {
        switch authorization {
        case .authorized:
            PaceLocalization.text(
                de: "Pace darf dir Mitteilungen senden. Du kannst das jederzeit in den iOS-Einstellungen ändern.",
                en: "Pace may send you notifications. You can change this at any time in iOS Settings.",
                ru: "Pace может отправлять тебе уведомления. Это можно изменить в любое время в настройках iOS."
            )
        case .denied:
            Self.deniedMessage
        case .notDetermined, nil:
            PaceLocalization.text(
                de: "Erlaube Mitteilungen, damit Pace dich an dein Tagesziel erinnern kann.",
                en: "Allow notifications so Pace can remind you of your daily goal.",
                ru: "Разреши уведомления, чтобы Pace мог напоминать о дневной цели."
            )
        }
    }

    static var deniedMessage: String {
        PaceLocalization.text(
            de: "Mitteilungen für Pace sind ausgeschaltet. Du kannst sie in den iOS-Einstellungen einschalten.",
            en: "Notifications for Pace are turned off. You can turn them on in iOS Settings.",
            ru: "Уведомления для Pace выключены. Их можно включить в настройках iOS."
        )
    }

    /// Die Erinnerung ist eingeschaltet, iOS stellt aber keine Mitteilungen zu.
    public var reminderBlockedByPermission: Bool {
        reminder.isEnabled && authorization == .denied
    }

    // MARK: Erinnerung

    /// Schaltet die Erinnerung ein oder aus. Beim Einschalten wird – falls nötig – nach der Erlaubnis gefragt; ohne
    /// Erlaubnis bleibt sie aus.
    public func setReminderEnabled(_ enabled: Bool) async {
        guard let notifications, !isUpdating, enabled != reminder.isEnabled else { return }
        isUpdating = true
        defer { isUpdating = false }

        if enabled {
            var status = await notifications.authorization()
            if status == .notDetermined {
                _ = await notifications.requestAuthorization()
                status = await notifications.authorization()
            }
            authorization = status
            guard status == .authorized else {
                message = Self.deniedMessage
                return
            }
            message = nil
        }
        var updated = reminder
        updated.isEnabled = enabled
        settings.streakReminder = updated
        await reschedule()
    }

    /// Neue Uhrzeit (Stunde 0–23, Minute 0–59).
    public func setReminderTime(hour: Int, minute: Int) async {
        let updated = StreakReminderSettings(isEnabled: reminder.isEnabled, hour: hour, minute: minute)
        guard updated != reminder else { return }
        settings.streakReminder = updated
        await reschedule()
    }

    /// Plant die Erinnerung passend zu Einstellung, Sprache und heutigem Ziel – nur, wenn sich etwas geändert hat.
    public func reschedule() async {
        guard let notifications else { return }
        let reminder = reminder
        let plan: Plan? = reminder.isEnabled
            ? Plan(
                hour: reminder.hour,
                minute: reminder.minute,
                skipToday: isTodayGoalReached(),
                language: PaceLocalization.shared.effectiveLanguage
            )
            : nil
        if let lastPlan, lastPlan == plan { return }
        lastPlan = .some(plan)

        if let plan {
            await notifications.scheduleStreakReminders(
                hour: plan.hour,
                minute: plan.minute,
                skipToday: plan.skipToday,
                title: Self.reminderTitle,
                body: Self.reminderBody
            )
        } else {
            await notifications.cancelStreakReminders()
        }
    }

    /// Entfernt geplante Erinnerungen (z. B. nach dem Löschen des Kontos).
    public func cancelAll() async {
        lastPlan = .some(nil)
        await notifications?.cancelStreakReminders()
    }

    static var reminderTitle: String {
        PaceLocalization.text(de: "Dein Tagesziel wartet", en: "Your daily goal is waiting", ru: "Твоя дневная цель ждёт")
    }

    static var reminderBody: String {
        PaceLocalization.text(
            de: "Erreiche heute dein Tagesziel, um deine Serie fortzusetzen.",
            en: "Reach your daily goal today to keep your streak going.",
            ru: "Достигни сегодня дневной цели, чтобы продолжить свою серию."
        )
    }

    public var reminderExplanation: String {
        PaceLocalization.text(
            de: "Eine Mitteilung zur gewählten Uhrzeit, wenn du dein Tagesziel noch nicht erreicht hast. Ist es heute schon geschafft, erinnert dich Pace erst morgen wieder. Öffne Pace mindestens alle zwei Wochen, damit die Erinnerungen weiter geplant werden.",
            en: "A notification at the chosen time if you haven't reached your daily goal yet. If you already made it today, Pace reminds you again tomorrow. Open Pace at least every two weeks so reminders keep getting scheduled.",
            ru: "Уведомление в выбранное время, если ты ещё не достиг дневной цели. Если цель уже выполнена сегодня, Pace напомнит только завтра. Открывай Pace хотя бы раз в две недели, чтобы напоминания продолжали планироваться."
        )
    }

    public var pushNotice: String {
        PaceLocalization.text(
            de: "Mitteilungen zu Freundschaftsanfragen, Gruppeneinladungen und neuen Chatnachrichten folgen, sobald der Push-Versand auf dem Server eingerichtet ist. Bis dahin siehst du sie direkt im Social-Tab.",
            en: "Notifications for friend requests, group invitations and new chat messages will follow once push delivery is set up on the server. Until then you'll see them directly in the Social tab.",
            ru: "Уведомления о запросах в друзья, приглашениях в группы и новых сообщениях появятся, когда на сервере будет настроена push-рассылка. До тех пор ты увидишь их во вкладке «Друзья»."
        )
    }
}
