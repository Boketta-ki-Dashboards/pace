import Foundation

/// Zuletzt bekannter Stand zum Tagesziel (Wettbewerbsschritte aus HealthKit).
public struct GoalProgressSnapshot: Equatable, Sendable {
    public let day: LocalDate
    public let steps: Int
    public let goal: Int
    /// Zeitpunkt, zu dem die Schritte aus Apple Health gelesen wurden.
    public let measuredAt: Date

    public init(day: LocalDate, steps: Int, goal: Int, measuredAt: Date) {
        self.day = day
        self.steps = steps
        self.goal = goal
        self.measuredAt = measuredAt
    }

    public var isGoalReached: Bool { steps >= goal }
}

/// Eine geplante lokale Mitteilung.
public struct PlannedNotification: Equatable, Sendable {
    public let identifier: String
    /// Datum und Uhrzeit (Jahr, Monat, Tag, Stunde, Minute) in der Zeitzone des Geräts – Sommer-/Winterzeit
    /// berücksichtigt iOS beim Zustellen.
    public let dateComponents: DateComponents
    public let title: String
    public let body: String

    public init(identifier: String, dateComponents: DateComponents, title: String, body: String) {
        self.identifier = identifier
        self.dateComponents = dateComponents
        self.title = title
        self.body = body
    }
}

/// Plant die Tagesziel-Erinnerungen der nächsten Tage mit Texten, die zur Situation passen.
///
/// Grenzen von iOS: Lokale Mitteilungen werden im Voraus geplant; Pace kann Apple Health nicht unmittelbar vor der
/// Zustellung neu lesen. Deshalb
/// - nennt eine Erinnerung die fehlenden Schritte nur, wenn der bekannte Stand bei der Zustellung höchstens
///   ``freshness`` alt ist (sonst ein allgemeiner Text ohne Zahl – nie eine veraltete Restschrittzahl),
/// - entfallen die Erinnerungen von heute, sobald das Ziel erreicht ist (Pace plant bei jeder Aktualisierung neu),
/// - gibt es die Erfolgsmeldung nur, wenn Pace das Erreichen selbst mitbekommt.
public enum GoalReminderPlanner {
    public static let daysAhead = 14
    /// iOS behält höchstens 64 geplante Mitteilungen je App; Pace nutzt davon höchstens so viele für Erinnerungen.
    public static let maximumPending = 60
    /// Höchstes Alter des Schrittstands, damit eine Erinnerung die fehlenden Schritte nennt.
    public static let freshness: TimeInterval = 90 * 60
    /// Bis zu dieser Stunde gilt eine Erinnerung als Morgen-Erinnerung.
    public static let morningEndHour = 11
    public static let identifierPrefix = "pace.goal-reminder."
    public static let successIdentifierPrefix = "pace.goal-reached."

    /// - Parameters:
    ///   - goal: Tagesziel für heute und die folgenden Tage (Änderungen gelten ab heute).
    ///   - progress: Zuletzt bekannter Stand von heute; `nil`, wenn unbekannt.
    public static func plan(
        times: [ReminderTime],
        goal: Int,
        progress: GoalProgressSnapshot?,
        now: Date,
        calendar: ActivityCalendar
    ) -> [PlannedNotification] {
        let today = calendar.day(containing: now)
        let todayProgress = progress?.day == today ? progress : nil
        var notifications: [PlannedNotification] = []
        for offset in 0..<plannedDays(timesPerDay: times.count) {
            let day = calendar.adding(offset, to: today)
            if offset == 0, todayProgress?.isGoalReached == true { continue }
            for (index, time) in times.enumerated() {
                guard let fireDate = calendar.date(day, hour: time.hour, minute: time.minute), fireDate > now else { continue }
                let content = content(
                    time: time,
                    variant: day.day &+ index,
                    goal: goal,
                    progress: offset == 0 ? todayProgress : nil,
                    fireDate: fireDate
                )
                var components = DateComponents()
                components.year = day.year
                components.month = day.month
                components.day = day.day
                components.hour = time.hour
                components.minute = time.minute
                notifications.append(PlannedNotification(
                    identifier: identifierPrefix + "\(day.isoString)-" + String(format: "%02d%02d", time.hour, time.minute),
                    dateComponents: components,
                    title: content.title,
                    body: content.body
                ))
            }
        }
        return notifications
    }

    /// Für so viele Tage wird im Voraus geplant (bei vielen Uhrzeiten weniger, wegen der iOS-Grenze).
    public static func plannedDays(timesPerDay: Int) -> Int {
        max(1, min(daysAhead, maximumPending / max(timesPerDay, 1)))
    }

    /// Text einer Erinnerung.
    static func content(
        time: ReminderTime,
        variant: Int,
        goal: Int,
        progress: GoalProgressSnapshot?,
        fireDate: Date
    ) -> (title: String, body: String) {
        let goalSteps = PaceLocalization.steps(goal)
        if time.hour < morningEndHour {
            let title = PaceLocalization.text(
                de: "Vergiss dein Tagesziel nicht!", en: "Don't forget your daily goal!", ru: "Не забудь о дневной цели!"
            )
            let body = variant % 2 == 0
                ? PaceLocalization.text(
                    de: "Heute stehen \(goalSteps) an – jeder Weg zählt.",
                    en: "\(goalSteps) are on today – every walk counts.",
                    ru: "Сегодня в планах \(goalSteps) – важен каждый путь."
                )
                : PaceLocalization.text(
                    de: "Ein kurzer Spaziergang am Morgen bringt dich deinem Tagesziel näher.",
                    en: "A short morning walk brings you closer to your daily goal.",
                    ru: "Короткая утренняя прогулка приблизит тебя к дневной цели."
                )
            return (title, body)
        }
        if let progress, !progress.isGoalReached, fireDate.timeIntervalSince(progress.measuredAt) <= freshness {
            let remaining = progress.goal - progress.steps
            let remainingSteps = PaceLocalization.steps(remaining)
            if remaining <= max(500, progress.goal / 10) {
                return (
                    PaceLocalization.text(
                        de: "Nur noch \(remainingSteps)!", en: "Only \(remainingSteps) to go!", ru: "Осталось всего \(remainingSteps)!"
                    ),
                    PaceLocalization.text(
                        de: "Dein Tagesziel ist fast geschafft.", en: "Your daily goal is almost done.", ru: "Дневная цель почти выполнена."
                    )
                )
            }
            return (
                PaceLocalization.text(de: "Dein Tagesziel wartet", en: "Your daily goal is waiting", ru: "Твоя дневная цель ждёт"),
                PaceLocalization.text(
                    de: "Dir fehlen noch \(remainingSteps) bis zu deinem Tagesziel.",
                    en: "You need \(remainingSteps) more to reach your daily goal.",
                    ru: "До дневной цели осталось \(remainingSteps)."
                )
            )
        }
        let title = PaceLocalization.text(de: "Dein Tagesziel wartet", en: "Your daily goal is waiting", ru: "Твоя дневная цель ждёт")
        let body = variant % 2 == 0
            ? PaceLocalization.text(
                de: "Noch ist Zeit für deine \(goalSteps) heute.",
                en: "There's still time for your \(goalSteps) today.",
                ru: "Ещё есть время пройти сегодня \(goalSteps)."
            )
            : PaceLocalization.text(
                de: "Ein Spaziergang zählt – hol dir heute dein Tagesziel.",
                en: "A walk counts – reach your daily goal today.",
                ru: "Каждая прогулка важна – достигни сегодня дневной цели."
            )
        return (title, body)
    }

    /// Erfolgsmeldung, sobald das Ziel erreicht ist (einmal am Tag).
    public static func success(steps: Int, day: LocalDate) -> PlannedNotification {
        PlannedNotification(
            identifier: successIdentifierPrefix + day.isoString,
            dateComponents: DateComponents(),
            title: PaceLocalization.text(de: "Geschafft!", en: "Done!", ru: "Готово!"),
            body: PaceLocalization.text(
                de: "Du hast dein Tagesziel erreicht – \(PaceLocalization.steps(steps)) heute.",
                en: "You reached your daily goal – \(PaceLocalization.steps(steps)) today.",
                ru: "Ты достиг дневной цели – сегодня \(PaceLocalization.steps(steps))."
            )
        )
    }
}
