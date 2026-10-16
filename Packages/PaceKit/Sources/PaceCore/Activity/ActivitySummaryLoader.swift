import Foundation

/// Ergebnis beim Laden der Bewegungsdaten.
public enum ActivityLoadResult: Equatable, Sendable {
    case available(ActivityOverview)
    /// Es ist kein einziges Schritt-Sample lesbar – in der Praxis fehlt der Lesezugriff.
    case noReadAccess
}

/// Lädt die Bewegungsdaten der letzten 7 Tage und leitet daraus alle Zeiträume ab.
///
/// Die letzten 7 Tage enthalten immer auch „heute“, „gestern“ und die aktuelle ISO-Woche, deshalb genügt
/// ein Ladevorgang pro Kennzahl.
///
/// HealthKit verrät aus Datenschutzgründen nicht, ob der Lesezugriff verweigert wurde – ohne Zugriff sind schlicht
/// keine Samples sichtbar. Deshalb gilt je Kennzahl:
/// - Samples im Zeitraum → Tage ohne Samples zählen als `0`.
/// - Keine Samples im Zeitraum, aber irgendwann welche → ebenfalls `0`.
/// - Überhaupt keine Samples lesbar → Kennzahl nicht verfügbar (`nil`). Bei Schritten: `.noReadAccess`.
public struct ActivitySummaryLoader: Sendable {
    private let provider: any ActivityDataProviding
    private let calendar: ActivityCalendar
    private let now: @Sendable () -> Date

    public init(
        provider: any ActivityDataProviding,
        calendar: ActivityCalendar = ActivityCalendar(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.calendar = calendar
        self.now = now
    }

    public func load() async throws -> ActivityLoadResult {
        let currentDate = now()
        let today = calendar.day(containing: currentDate)
        let range = ActivityPeriod.lastSevenDays.dayRange(endingOn: today, calendar: calendar)

        async let steps = totals(.steps, range)
        async let competitionSteps = totals(.competitionSteps, range)
        async let distance = totals(.walkingRunningDistance, range)
        async let energy = totals(.activeEnergy, range)
        async let flights = totals(.flightsClimbed, range)
        async let exercise = totals(.exerciseTime, range)

        guard let stepTotals = try await steps else {
            return .noReadAccess
        }
        // Wettbewerbsschritte sind eine Teilmenge der Schritte: Sind Schritte lesbar, fehlen nur manuelle Tage.
        let competitionTotals = try await competitionSteps ?? [:]
        let distanceTotals = try await distance
        let energyTotals = try await energy
        let flightTotals = try await flights
        let exerciseTotals = try await exercise

        let days = calendar.days(from: range.lowerBound, through: range.upperBound).map { day in
            DailyActivitySummary(
                date: day,
                healthSteps: Self.integer(stepTotals[day]),
                competitionSteps: Self.integer(competitionTotals[day]),
                walkingRunningDistanceMeters: distanceTotals.map { $0[day] ?? 0 },
                activeEnergyKilocalories: energyTotals.map { $0[day] ?? 0 },
                flightsClimbed: flightTotals.map { Self.integer($0[day]) },
                exerciseMinutes: exerciseTotals.map { Self.integer($0[day]) }
            )
        }

        return .available(makeOverview(days: days, today: today, updatedAt: currentDate))
    }

    /// Tageswerte einer Kennzahl oder `nil`, wenn die Kennzahl gar nicht lesbar ist.
    private func totals(_ metric: ActivityMetric, _ range: ClosedRange<LocalDate>) async throws -> [LocalDate: Double]? {
        let totals = try await provider.dailyTotals(of: metric, for: range, calendar: calendar)
        if !totals.isEmpty {
            return totals
        }
        let availabilityMetric: ActivityMetric = metric == .competitionSteps ? .steps : metric
        return try await provider.hasAnySamples(of: availabilityMetric) ? [:] : nil
    }

    private func makeOverview(days: [DailyActivitySummary], today: LocalDate, updatedAt: Date) -> ActivityOverview {
        func summary(_ period: ActivityPeriod) -> ActivityPeriodSummary {
            let range = period.dayRange(endingOn: today, calendar: calendar)
            return ActivityPeriodSummary(period: period, days: days.filter { range.contains($0.date) })
        }
        let byDay = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
        return ActivityOverview(
            today: byDay[today]!,
            yesterday: byDay[calendar.adding(-1, to: today)]!,
            currentWeek: summary(.currentWeek),
            lastSevenDays: summary(.lastSevenDays),
            updatedAt: updatedAt
        )
    }

    private static func integer(_ value: Double?) -> Int {
        Int((value ?? 0).rounded())
    }
}
