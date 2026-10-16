import Foundation

/// Ergebnis beim Laden der heutigen Schritte.
public enum TodayStepsResult: Equatable, Sendable {
    case available(DailyStepCount)
    /// Es ist kein einziges Schritt-Sample lesbar – in der Praxis fehlt der Lesezugriff.
    case noReadAccess
}

/// Lädt die Schrittzahl des aktuellen Kalendertags.
///
/// HealthKit verrät aus Datenschutzgründen nicht, ob der Nutzer den *Lesezugriff* verweigert hat:
/// Ohne Zugriff sind schlicht keine Samples sichtbar. Liefert der heutige Tag keine Daten, prüft der Loader daher,
/// ob überhaupt Schrittdaten lesbar sind. Wenn nicht, wird das als fehlender Zugriff gemeldet, statt fälschlich
/// „0 Schritte“ anzuzeigen.
public struct TodayStepsLoader: Sendable {
    private let provider: any StepCountProviding
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        provider: any StepCountProviding,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.calendar = calendar
        self.now = now
    }

    public func load() async throws -> TodayStepsResult {
        let currentDate = now()
        let today = todayInterval(containing: currentDate)

        if let steps = try await provider.stepCount(in: today) {
            return .available(DailyStepCount(day: today.start, steps: steps, updatedAt: currentDate))
        }

        guard try await provider.hasAnyStepSamples() else {
            return .noReadAccess
        }
        return .available(DailyStepCount(day: today.start, steps: 0, updatedAt: currentDate))
    }

    private func todayInterval(containing date: Date) -> DateInterval {
        if let interval = calendar.dateInterval(of: .day, for: date) {
            return interval
        }
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        return DateInterval(start: start, end: max(end, date))
    }
}
