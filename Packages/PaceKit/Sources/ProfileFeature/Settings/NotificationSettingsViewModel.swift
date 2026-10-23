import Foundation
import Observation
import PaceCore

/// Mitteilungen: Erlaubnis von iOS und die lokalen Erinnerungen an das Tagesziel (eine oder mehrere Uhrzeiten).
///
/// Die Erinnerungen werden für die nächsten Tage im Voraus geplant (ohne Server, siehe ``GoalReminderPlanner``):
/// Texte passend zur Tageszeit und – solange der Stand frisch ist – mit den fehlenden Schritten; ist das Ziel heute
/// erreicht, entfallen die heutigen. Neu geplant wird beim Start der App, bei neuen Schrittwerten (höchstens alle
/// paar Minuten), beim Erreichen des Ziels, bei geänderten Uhrzeiten und beim Sprachwechsel. Push-Mitteilungen
/// (Anfragen, Einladungen, Chat bei geschlossener App) brauchen einen Push-Dienst und werden nicht angeboten.
@MainActor
@Observable
public final class NotificationSettingsViewModel {
    /// Neue Schrittwerte planen höchstens so oft neu (Uhrzeiten, Sprache und Zielerreichung sofort).
    static let minimumRescheduleInterval: TimeInterval = 5 * 60

    /// Erlaubnis von iOS; `nil`, solange sie nicht abgefragt wurde.
    public private(set) var authorization: NotificationAuthorization?
    public private(set) var isUpdating = false
    /// Hinweis nach einer abgelehnten Erlaubnis.
    public private(set) var message: String?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let notifications: (any LocalNotificationScheduling)?
    @ObservationIgnored private let isTodayGoalReached: @MainActor () -> Bool
    @ObservationIgnored private let todayProgress: @MainActor () -> GoalProgressSnapshot?
    @ObservationIgnored private let currentGoal: @MainActor () -> Int
    @ObservationIgnored private let calendar: ActivityCalendar
    @ObservationIgnored private let now: @Sendable () -> Date
    /// Zuletzt an iOS übergebene Erinnerungen und wann.
    @ObservationIgnored private var lastPlan: [PlannedNotification]?
    @ObservationIgnored private var lastScheduledAt: Date?
    @ObservationIgnored private var lastPlanLanguage: AppLanguage?
    /// Tag, an dem Pace das Ziel zuletzt noch offen gesehen hat – „Geschafft!“ nur nach einem selbst erlebten Wechsel.
    @ObservationIgnored private var sawGoalOpenOn: LocalDate?

    /// - Parameters:
    ///   - isTodayGoalReached: Ob das heutige Tagesziel schon erreicht ist (dann entfallen die heutigen Erinnerungen).
    ///   - todayProgress: Zuletzt bekannter Stand von heute aus Apple Health (für Texte mit fehlenden Schritten).
    ///   - currentGoal: Aktuelles Tagesziel (für Texte ohne bekannten Stand).
    public init(
        settings: AppSettings,
        notifications: (any LocalNotificationScheduling)?,
        isTodayGoalReached: @escaping @MainActor () -> Bool = { false },
        todayProgress: @escaping @MainActor () -> GoalProgressSnapshot? = { nil },
        currentGoal: @escaping @MainActor () -> Int = { StepGoalRules.defaultGoal },
        calendar: ActivityCalendar = ActivityCalendar(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.settings = settings
        self.notifications = notifications
        self.isTodayGoalReached = isTodayGoalReached
        self.todayProgress = todayProgress
        self.currentGoal = currentGoal
        self.calendar = calendar
        self.now = now
    }

    /// Ohne angebundene Mitteilungen (z. B. Tests) zeigt die Seite einen ehrlichen Hinweis.
    public var isAvailable: Bool { notifications != nil }

    public var reminder: StreakReminderSettings { settings.streakReminder }

    /// Ob das heutige Ziel erreicht ist – für Auslöser in der Oberfläche (neu planen, sobald es sich ändert).
    public var todayGoalReached: Bool { isTodayGoalReached() || todayProgress()?.isGoalReached == true }

    /// Uhrzeit, z. B. `19:00` bzw. `7:00 PM`.
    public func timeText(_ time: ReminderTime) -> String {
        let components = DateComponents(hour: time.hour, minute: time.minute)
        guard let date = Calendar(identifier: .gregorian).date(from: components) else {
            return String(format: "%02d:%02d", time.hour, time.minute)
        }
        var style = Date.FormatStyle.pace(Date.FormatStyle(date: .omitted, time: .shortened))
        style.timeZone = Calendar(identifier: .gregorian).timeZone
        return date.formatted(style)
    }

    /// Alle Uhrzeiten, z. B. `8:00 · 12:30 · 19:00`.
    public var reminderTimeText: String {
        reminder.times.map(timeText).joined(separator: " · ")
    }

    /// Kurzfassung für die Profilseite: „Aus“, „19:00“ oder „3 Erinnerungen“.
    public var reminderSummary: String {
        guard reminder.isEnabled else { return ProfileTexts.off }
        let count = reminder.times.count
        guard count > 1 else { return timeText(reminder.times[0]) }
        return PaceLocalization.plural(
            count,
            de: ("\(count) Erinnerung", "\(count) Erinnerungen"),
            en: ("\(count) reminder", "\(count) reminders"),
            ru: ("\(count) напоминание", "\(count) напоминания", "\(count) напоминаний")
        )
    }

    /// Uhrzeit als Datum für die Zeitauswahl (heute zur gewählten Uhrzeit).
    public func date(for time: ReminderTime) -> Date {
        let today = now()
        return Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: today) ?? today
    }

    /// Erste Uhrzeit als Datum (für ältere Aufrufer).
    public var reminderDate: Date { date(for: reminder.times[0]) }

    /// Übernimmt Stunde und Minute aus der Zeitauswahl für die erste Uhrzeit.
    public func setReminderTime(_ date: Date) async {
        await updateReminderTime(reminder.times[0], to: date)
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

    /// Schaltet die Erinnerungen ein oder aus. Beim Einschalten wird – falls nötig – nach der Erlaubnis gefragt; ohne
    /// Erlaubnis bleiben sie aus.
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

    /// Neue Uhrzeit für die erste Erinnerung (Stunde 0–23, Minute 0–59).
    public func setReminderTime(hour: Int, minute: Int) async {
        await updateReminderTime(reminder.times[0], to: ReminderTime(hour: hour, minute: minute))
    }

    /// Weitere Uhrzeit hinzufügen (ohne Angabe ein Vorschlag in einer Lücke des Tages).
    public func addReminderTime(_ time: ReminderTime? = nil) async {
        var updated = reminder
        updated.add(time ?? reminder.suggestedNextTime)
        guard updated != reminder else { return }
        settings.streakReminder = updated
        await reschedule()
    }

    public func removeReminderTime(_ time: ReminderTime) async {
        var updated = reminder
        updated.remove(time)
        guard updated != reminder else { return }
        settings.streakReminder = updated
        await reschedule()
    }

    /// Ändert eine Uhrzeit auf die in der Zeitauswahl gewählte.
    public func updateReminderTime(_ time: ReminderTime, to date: Date) async {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        await updateReminderTime(time, to: ReminderTime(hour: parts.hour ?? time.hour, minute: parts.minute ?? time.minute))
    }

    public func updateReminderTime(_ time: ReminderTime, to newTime: ReminderTime) async {
        var updated = reminder
        updated.replace(time, with: newTime)
        guard updated != reminder else { return }
        settings.streakReminder = updated
        await reschedule()
    }

    /// Neue Schrittwerte aus Apple Health: einmal am Tag „Geschafft!“, wenn Pace das Erreichen miterlebt, und die
    /// kommenden Erinnerungen mit frischem Stand neu planen (gedrosselt).
    public func progressDidChange() async {
        if reminder.isEnabled, let progress = todayProgress(), progress.day == calendar.day(containing: now()) {
            if !progress.isGoalReached {
                sawGoalOpenOn = progress.day
            } else if sawGoalOpenOn == progress.day, settings.goalReachedNotifiedOn != progress.day {
                settings.goalReachedNotifiedOn = progress.day
                await notifications?.deliver(GoalReminderPlanner.success(steps: progress.steps, day: progress.day))
            }
        }
        await reschedule(force: false)
    }

    /// Plant die Erinnerungen passend zu Uhrzeiten, Sprache, Ziel und Stand – nur, wenn sich etwas geändert hat.
    /// - Parameter force: `false` bei reinen Schritt-Aktualisierungen: dann höchstens alle
    ///   ``minimumRescheduleInterval`` neu, außer heutige Erinnerungen fallen weg (Ziel erreicht).
    public func reschedule(force: Bool = true) async {
        guard let notifications else { return }
        let currentDate = now()
        let progress = todayProgress()
        var planned: [PlannedNotification] = []
        if reminder.isEnabled {
            let today = calendar.day(containing: currentDate)
            var planProgress = progress?.day == today ? progress : nil
            if isTodayGoalReached(), planProgress?.isGoalReached != true {
                // Laut Serie heute erreicht, der Schrittstand fehlt aber: die heutigen Erinnerungen entfallen trotzdem.
                planProgress = GoalProgressSnapshot(
                    day: today, steps: currentGoal(), goal: currentGoal(), measuredAt: currentDate
                )
            }
            planned = GoalReminderPlanner.plan(
                times: reminder.times,
                goal: progress?.goal ?? currentGoal(),
                progress: planProgress,
                now: currentDate,
                calendar: calendar
            )
        }
        let language = PaceLocalization.shared.effectiveLanguage
        if let lastPlan, lastPlan == planned, lastPlanLanguage == language { return }
        if !force, let lastPlan, let lastScheduledAt, lastPlanLanguage == language,
           lastPlan.map(\.identifier) == planned.map(\.identifier),
           currentDate.timeIntervalSince(lastScheduledAt) < Self.minimumRescheduleInterval {
            return
        }
        lastPlan = planned
        lastScheduledAt = currentDate
        lastPlanLanguage = language
        if planned.isEmpty {
            await notifications.cancelGoalReminders()
        } else {
            await notifications.scheduleGoalReminders(planned)
        }
    }

    // MARK: Chat

    /// Hinweis auf neue Chatnachrichten, solange Pace geöffnet ist (kein Push bei geschlossener App).
    public var chatMessageHints: Bool { settings.chatMessageHints }

    /// Schaltet die Hinweise ein oder aus. Beim Einschalten wird – falls noch nicht geschehen – nach der Erlaubnis
    /// gefragt.
    public func setChatMessageHints(_ enabled: Bool) async {
        guard let notifications, !isUpdating, enabled != chatMessageHints else { return }
        settings.chatMessageHints = enabled
        guard enabled else { return }
        isUpdating = true
        defer { isUpdating = false }
        var status = await notifications.authorization()
        if status == .notDetermined {
            _ = await notifications.requestAuthorization()
            status = await notifications.authorization()
        }
        authorization = status
        message = status == .authorized ? nil : Self.deniedMessage
    }

    public var chatHintExplanation: String {
        PaceLocalization.text(
            de: "Solange Pace geöffnet ist, erscheint bei einer neuen Nachricht ein Hinweis – außer im gerade offenen Chat.",
            en: "While Pace is open, a new message shows an alert – except in the chat you're viewing.",
            ru: "Пока Pace открыт, о новом сообщении появится уведомление – кроме открытого сейчас чата."
        )
    }

    /// Zeigt den Hinweis auf eine neue Nachricht – nur, wenn eingeschaltet und von iOS erlaubt.
    public func announceIncomingMessage(_ notification: PlannedNotification) async {
        guard chatMessageHints, let notifications else { return }
        guard await notifications.authorization() == .authorized else { return }
        await notifications.deliver(notification)
    }

    /// Entfernt geplante Erinnerungen (z. B. nach dem Löschen des Kontos).
    public func cancelAll() async {
        lastPlan = []
        lastScheduledAt = now()
        await notifications?.cancelGoalReminders()
    }

    public var reminderExplanation: String {
        PaceLocalization.text(
            de: "Mitteilungen zu deinen Uhrzeiten – morgens als Erinnerung, später mit den fehlenden Schritten, sofern Pace einen aktuellen Stand kennt. iOS plant Mitteilungen im Voraus: Pace kann Apple Health nicht direkt vor der Zustellung lesen. Ist dein Ziel erreicht und war Pace seitdem geöffnet, entfallen die restlichen Erinnerungen des Tages. Öffne Pace mindestens alle \(GoalReminderPlanner.plannedDays(timesPerDay: reminder.times.count)) Tage, damit weiter geplant wird.",
            en: "Notifications at your times – a reminder in the morning, later with the steps you still need if Pace knows a recent count. iOS schedules notifications in advance: Pace can't read Apple Health right before delivery. Once your goal is reached and Pace was opened since, the remaining reminders for the day are skipped. Open Pace at least every \(GoalReminderPlanner.plannedDays(timesPerDay: reminder.times.count)) days so reminders keep being scheduled.",
            ru: "Уведомления в выбранное время – утром как напоминание, позже с оставшимися шагами, если Pace знает актуальное значение. iOS планирует уведомления заранее: Pace не может прочитать данные «Здоровья» прямо перед доставкой. Если цель достигнута и после этого Pace открывался, остальные напоминания за день не придут. Открывай Pace хотя бы раз в \(GoalReminderPlanner.plannedDays(timesPerDay: reminder.times.count)) дн., чтобы напоминания продолжали планироваться."
        )
    }

    public var pushNotice: String {
        PaceLocalization.text(
            de: "Bei geschlossener App bräuchte Pace Push-Mitteilungen über Apple (APNs) und einen Versand vom Server – das ist noch nicht eingerichtet. Freundschaftsanfragen, Gruppeneinladungen und neue Nachrichten siehst du bis dahin im Social-Tab.",
            en: "When the app is closed, Pace would need push notifications via Apple (APNs) and delivery from the server – this isn't set up yet. Until then you'll see friend requests, group invitations and new messages in the Social tab.",
            ru: "Когда приложение закрыто, Pace нужны push-уведомления через Apple (APNs) и отправка с сервера – это пока не настроено. До тех пор запросы в друзья, приглашения в группы и новые сообщения видны во вкладке «Друзья»."
        )
    }
}
