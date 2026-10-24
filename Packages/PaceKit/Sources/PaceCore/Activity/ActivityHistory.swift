import Foundation

/// Ergebnis beim Laden eines längeren Verlaufs.
public enum ActivityHistoryLoadResult: Equatable, Sendable {
    case available(ActivityHistory)
    /// Es ist kein einziges Schritt-Sample lesbar – in der Praxis fehlt der Lesezugriff.
    case noReadAccess
}

/// Tageswerte über einen längeren Zeitraum (z. B. die letzten 12 Monate) für Statistiken, Bestwerte und Streak.
///
/// Nach dem Laden hat jeder Tag in `range` einen Eintrag (Tage ohne Samples mit `0`); Kennzahlen, die gar nicht
/// lesbar sind, bleiben wie in `DailyActivitySummary` `nil`. Tage außerhalb von `range` sind unbekannt.
public struct ActivityHistory: Equatable, Sendable {
    public let range: ClosedRange<LocalDate>
    /// Zeitpunkt, zu dem der Verlauf gelesen wurde.
    public let updatedAt: Date
    private let days: [LocalDate: DailyActivitySummary]

    public init(days: [DailyActivitySummary], range: ClosedRange<LocalDate>, updatedAt: Date) {
        self.range = range
        self.updatedAt = updatedAt
        self.days = Dictionary(days.filter { range.contains($0.date) }.map { ($0.date, $0) }) { _, newer in newer }
    }

    /// Tageswert; `nil` für unbekannte Tage (außerhalb des geladenen Zeitraums).
    public func summary(for day: LocalDate) -> DailyActivitySummary? {
        days[day]
    }

    /// Alle bekannten Tage von `first` bis `last`, chronologisch.
    public func summaries(from first: LocalDate, through last: LocalDate, calendar: ActivityCalendar) -> [DailyActivitySummary] {
        let lower = max(first, range.lowerBound)
        let upper = min(last, range.upperBound)
        return calendar.days(from: lower, through: upper).compactMap(summary(for:))
    }

    /// Alle Tage mit geschätzten aktiven Kalorien, wo Apple Health keine gemessenen liefert (siehe
    /// ``DailyActivitySummary/estimatingActiveEnergy(with:)``).
    public func estimatingActiveEnergy(with metrics: BodyMetrics) -> ActivityHistory {
        ActivityHistory(days: days.values.map { $0.estimatingActiveEnergy(with: metrics) }, range: range, updatedAt: updatedAt)
    }

    /// Ersetzt Tage durch neuere Werte (z. B. die live aktualisierten letzten 7 Tage) und erweitert den Zeitraum bis
    /// zum jüngsten dieser Tage (Tageswechsel). Ältere Tage außerhalb des Zeitraums werden ignoriert.
    public func merging(_ newer: [DailyActivitySummary]) -> ActivityHistory {
        guard let latest = newer.map(\.date).max() else { return self }
        let upper = max(range.upperBound, latest)
        var merged = days
        for day in newer where day.date >= range.lowerBound {
            merged[day.date] = day
        }
        // Liegt zwischen altem Ende und den neuen Werten eine Lücke (Verlauf seit Tagen nicht neu geladen), bleiben diese
        // Tage unbekannt (`summary(for:)` liefert `nil`) statt als 0 zu erscheinen.
        return ActivityHistory(days: Array(merged.values), range: range.lowerBound...upper, updatedAt: updatedAt)
    }
}
