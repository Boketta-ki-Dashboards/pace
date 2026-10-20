import ActivityFeature
import Foundation
import PaceCore

/// Inhalt des Widgets „Persönliche Streak“ in allen Größen. Reine Berechnung, dadurch testbar.
///
/// Die Serie zählt aufeinanderfolgende Tage mit erreichtem Tagesziel (Ziel laut Zielverlauf). Ist die Serie gerade
/// unterbrochen, können im Verlauf trotzdem erreichte Tage stehen – die Texte machen den Unterschied deutlich.
public struct HomeStreakWidget: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public let date: LocalDate
        public let status: StepStreakDayStatus
        /// Erster Buchstabe des Wochentags.
        public let letter: String
        public let isToday: Bool
        public let accessibilityLabel: String

        public var id: LocalDate { date }
    }

    public let current: Int
    public let isTodayReached: Bool
    /// Die Serie reicht bis zum Beginn des geladenen Verlaufs (sie kann länger sein).
    public let reachesHistoryStart: Bool
    public let recordDays: Int?
    /// Laufende Woche, Montag bis Sonntag.
    public let week: [Day]
    /// Die laufende und die drei vorherigen Kalenderwochen (28 Tage, ab Montag).
    public let fourWeeks: [Day]
    /// Erreichte Tage in den letzten 30 Tagen (bis heute).
    public let reachedLast30Days: Int
    /// Erreichte Tage in der laufenden Woche.
    public let reachedThisWeek: Int

    public init(
        streak: StepStreak,
        record: StepStreakRecord?,
        recentDays: [(day: LocalDate, status: StepStreakDayStatus)],
        formatter: ActivityFormatter
    ) {
        current = streak.current
        isTodayReached = streak.isTodayReached
        reachesHistoryStart = streak.reachesHistoryStart
        recordDays = record.flatMap { $0.days > 0 ? $0.days : nil }

        guard let today = recentDays.last?.day else {
            week = []
            fourWeeks = []
            reachedLast30Days = 0
            reachedThisWeek = 0
            return
        }
        let calendar = formatter.calendar
        let statuses = Dictionary(recentDays.map { ($0.day, $0.status) }, uniquingKeysWith: { _, last in last })
        let weekStart = calendar.startOfWeek(containing: today)
        let days = calendar.days(from: calendar.adding(-21, to: weekStart), through: calendar.adding(6, to: weekStart)).map { day in
            let status = statuses[day] ?? (day > today ? .future : .unknown)
            return Day(
                date: day,
                status: status,
                letter: HomeFormat.weekdayLetter(day, formatter: formatter),
                isToday: day == today,
                accessibilityLabel: "\(formatter.dayLong(day)): \(Self.statusTitle(status))"
            )
        }
        fourWeeks = days
        week = Array(days.suffix(7))
        let lastThirty = calendar.adding(-29, to: today)
        reachedLast30Days = recentDays.filter { $0.day >= lastThirty && $0.status == .reached }.count
        reachedThisWeek = week.filter { $0.status == .reached }.count
    }

    /// Zahl der Serie, z. B. `5` oder `400+`.
    public var currentNumberText: String {
        current.paceFormatted + (reachesHistoryStart ? "+" : "")
    }

    /// Einheit zur Zahl, z. B. `Tage`, `Tag`.
    public var unitText: String {
        PaceLocalization.plural(current, de: ("Tag", "Tage"), en: ("day", "days"), ru: ("день", "дня", "дней"))
    }

    /// z. B. `5 Tage`, `1 Tag`, `400+ Tage`.
    public var currentText: String {
        "\(currentNumberText) \(unitText)"
    }

    /// z. B. `12 Tage`; `nil` ohne Rekord.
    public var recordText: String? {
        recordDays.map { PaceLocalization.days($0) }
    }

    /// Was heute zu tun ist bzw. wie es steht – auch wenn die Serie unterbrochen ist.
    public var statusText: String {
        if isTodayReached {
            return PaceLocalization.text(de: "Heute geschafft – weiter so!", en: "Done for today – keep it up!", ru: "Сегодня выполнено – так держать!")
        }
        if current > 0 {
            return PaceLocalization.text(
                de: "Erreiche heute dein Tagesziel, um deine Serie fortzusetzen.",
                en: "Reach your daily goal today to keep your streak going.",
                ru: "Выполни сегодня дневную цель, чтобы продолжить серию."
            )
        }
        if reachedThisWeek > 0 {
            let count = reachedThisWeek.paceFormatted
            return PaceLocalization.text(
                de: "Gerade keine laufende Serie – diese Woche hast du dein Ziel an \(count) "
                    + "\(reachedThisWeek == 1 ? "Tag" : "Tagen") erreicht.",
                en: "No active streak right now – you reached your goal on \(count) "
                    + "\(reachedThisWeek == 1 ? "day" : "days") this week.",
                ru: "Сейчас серии нет – на этой неделе цель выполнена \(count) "
                    + PaceLocalization.plural(reachedThisWeek, de: ("", ""), en: ("", ""), ru: ("раз", "раза", "раз")) + "."
            )
        }
        return PaceLocalization.text(
            de: "Erreiche heute dein Tagesziel, um eine neue Serie zu starten.",
            en: "Reach your daily goal today to start a new streak.",
            ru: "Выполни сегодня дневную цель, чтобы начать новую серию."
        )
    }

    /// Kurzer Status für kleine Widgets, z. B. `Heute geschafft` oder `Heute offen`.
    public var shortStatusText: String {
        if isTodayReached {
            return PaceLocalization.text(de: "Heute geschafft", en: "Done today", ru: "Сегодня выполнено")
        }
        return PaceLocalization.text(de: "Heute offen", en: "Open today", ru: "Сегодня в процессе")
    }

    /// z. B. `18 von 30 Tagen erreicht`.
    public var last30DaysText: String {
        let count = reachedLast30Days.paceFormatted
        return PaceLocalization.text(
            de: "\(count) von 30 Tagen erreicht",
            en: "Reached on \(count) of 30 days",
            ru: "Выполнено в \(count) из 30 дней"
        )
    }

    public var accessibilityLabel: String {
        var parts = [
            PaceLocalization.text(de: "Persönliche Serie: \(currentText)", en: "Personal streak: \(currentText)", ru: "Личная серия: \(currentText)"),
            statusText,
        ]
        if let recordText {
            parts.append(PaceLocalization.text(de: "Rekord: \(recordText)", en: "Record: \(recordText)", ru: "Рекорд: \(recordText)"))
        }
        return parts.map { $0.hasSuffix(".") || $0.hasSuffix("!") ? $0 : $0 + "." }.joined(separator: " ")
    }

    static func statusTitle(_ status: StepStreakDayStatus) -> String {
        switch status {
        case .reached: PaceLocalization.text(de: "Ziel erreicht", en: "goal reached", ru: "цель выполнена")
        case .missed: PaceLocalization.text(de: "Ziel nicht erreicht", en: "goal missed", ru: "цель не выполнена")
        case .pending: PaceLocalization.text(de: "heute noch offen", en: "still open today", ru: "сегодня ещё в процессе")
        case .unknown: PaceLocalization.text(de: "keine Daten", en: "no data", ru: "нет данных")
        case .future: PaceLocalization.text(de: "noch nicht erreicht", en: "upcoming", ru: "ещё впереди")
        }
    }
}
