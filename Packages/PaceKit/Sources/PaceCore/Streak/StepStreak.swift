import Foundation

/// Persönliche Serie: aufeinanderfolgende Tage, an denen die Wettbewerbsschritte das an diesem Tag gültige Ziel
/// erreicht haben.
///
/// - Tagesgrenzen: Kalendertage in der Zeitzone des Geräts (`ActivityCalendar`), wie bei allen Tageswerten.
/// - Der laufende Tag zählt mit, sobald das Ziel erreicht ist, beendet die Serie aber nie vorzeitig.
/// - Jeder Tag zählt höchstens einmal (ein Tageswert pro Tag).
/// - Maßgeblich ist das Ziel des jeweiligen Tages (`StepGoalHistory`); spätere Zieländerungen wirken nicht zurück.
/// - Werte werden bei jeder Aktualisierung neu berechnet, nachträglich synchronisierte Health-Daten (z. B. von der
///   Apple Watch) fließen dadurch automatisch ein.
public struct StepStreak: Equatable, Sendable {
    /// Aktuelle Serie in Tagen.
    public let current: Int
    public let currentStart: LocalDate?
    /// Ob das Ziel heute schon erreicht ist (dann zählt heute in `current` mit).
    public let isTodayReached: Bool
    /// Längste Serie im ausgewerteten Zeitraum.
    public let longest: Int
    public let longestRange: ClosedRange<LocalDate>?
    /// Die aktuelle Serie beginnt am ersten ausgewerteten Tag – sie kann in Wahrheit länger sein.
    public let reachesHistoryStart: Bool

    public init(
        current: Int,
        currentStart: LocalDate?,
        isTodayReached: Bool,
        longest: Int,
        longestRange: ClosedRange<LocalDate>?,
        reachesHistoryStart: Bool
    ) {
        self.current = current
        self.currentStart = currentStart
        self.isTodayReached = isTodayReached
        self.longest = longest
        self.longestRange = longestRange
        self.reachesHistoryStart = reachesHistoryStart
    }

    public static let empty = StepStreak(
        current: 0, currentStart: nil, isTodayReached: false, longest: 0, longestRange: nil, reachesHistoryStart: false
    )
}

/// Status eines Tages für die Übersicht der erreichten Tage.
public enum StepStreakDayStatus: Equatable, Sendable {
    case reached
    case missed
    /// Heute, Ziel noch nicht erreicht – zählt (noch) nicht als verpasst.
    case pending
    /// Keine Daten für diesen Tag (außerhalb des geladenen Zeitraums).
    case unknown
    case future
}

public enum StepStreakCalculator {
    /// Ob das Ziel an diesem Tag erreicht wurde.
    public static func isReached(_ day: DailyActivitySummary, goals: StepGoalHistory) -> Bool {
        day.competitionSteps >= goals.goal(on: day.date)
    }

    /// Berechnet aktuelle und längste Serie aus dem Verlauf bis `today`.
    public static func streak(
        history: ActivityHistory,
        goals: StepGoalHistory,
        today: LocalDate,
        calendar: ActivityCalendar
    ) -> StepStreak {
        guard history.range.lowerBound <= today else { return .empty }

        var run = 0
        var runStart: LocalDate?
        var longest = 0
        var longestRange: ClosedRange<LocalDate>?
        var runBeforeToday = 0
        var runBeforeTodayStart: LocalDate?
        var isTodayReached = false

        for day in calendar.days(from: history.range.lowerBound, through: today) {
            let reached = history.summary(for: day).map { isReached($0, goals: goals) } ?? false
            if day == today {
                runBeforeToday = run
                runBeforeTodayStart = runStart
                isTodayReached = reached
            }
            if reached {
                if run == 0 { runStart = day }
                run += 1
                if run > longest, let runStart {
                    longest = run
                    longestRange = runStart...day
                }
            } else {
                run = 0
                runStart = nil
            }
        }

        let current = isTodayReached ? runBeforeToday + 1 : runBeforeToday
        let currentStart = isTodayReached ? (runBeforeTodayStart ?? today) : runBeforeTodayStart
        return StepStreak(
            current: current,
            currentStart: current > 0 ? currentStart : nil,
            isTodayReached: isTodayReached,
            longest: longest,
            longestRange: longestRange,
            reachesHistoryStart: current > 0 && currentStart == history.range.lowerBound
        )
    }

    /// Status je Tag von `first` bis `last` (für eine Kalender- oder Punktübersicht).
    public static func dayStatuses(
        history: ActivityHistory,
        goals: StepGoalHistory,
        from first: LocalDate,
        through last: LocalDate,
        today: LocalDate,
        calendar: ActivityCalendar
    ) -> [(day: LocalDate, status: StepStreakDayStatus)] {
        calendar.days(from: first, through: last).map { day in
            if day > today { return (day, .future) }
            guard let summary = history.summary(for: day) else { return (day, .unknown) }
            if isReached(summary, goals: goals) { return (day, .reached) }
            return (day, day == today ? .pending : .missed)
        }
    }
}

/// Bisher längste Serie. Wird auf dem Gerät gespeichert, damit sie über den geladenen Zeitraum hinaus erhalten bleibt.
/// Als eigenes, codierbares Modell vorbereitet für eine spätere Übertragung zwischen Geräten bzw. Konten.
public struct StepStreakRecord: Codable, Equatable, Sendable {
    public let days: Int
    public let start: LocalDate
    public let end: LocalDate

    public init(days: Int, start: LocalDate, end: LocalDate) {
        self.days = days
        self.start = start
        self.end = end
    }

    /// Der längere von gespeichertem Rekord und berechneter längster Serie (bei Gleichstand der gespeicherte).
    public static func best(stored: StepStreakRecord?, streak: StepStreak) -> StepStreakRecord? {
        guard let range = streak.longestRange, streak.longest > (stored?.days ?? 0) else { return stored }
        return StepStreakRecord(days: streak.longest, start: range.lowerBound, end: range.upperBound)
    }
}

/// Speichert den Streak-Rekord.
public protocol StepStreakRecordStoring: Sendable {
    func load() -> StepStreakRecord?
    func save(_ record: StepStreakRecord)
}

public struct UserDefaultsStepStreakRecordStore: StepStreakRecordStoring {
    private let suiteName: String?
    private let key = "pace.streak.record"

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    public func load() -> StepStreakRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StepStreakRecord.self, from: data)
    }

    public func save(_ record: StepStreakRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}

public final class InMemoryStepStreakRecordStore: StepStreakRecordStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: StepStreakRecord?

    public init(_ record: StepStreakRecord? = nil) {
        stored = record
    }

    public func load() -> StepStreakRecord? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    public func save(_ record: StepStreakRecord) {
        lock.lock()
        defer { lock.unlock() }
        stored = record
    }
}
