import Foundation

/// Alle Zeiträume, die Home und Statistiken benötigen, aus einem einzigen Ladevorgang.
public struct ActivityOverview: Equatable, Sendable {
    public let today: DailyActivitySummary
    public let yesterday: DailyActivitySummary
    public let currentWeek: ActivityPeriodSummary
    public let lastSevenDays: ActivityPeriodSummary
    /// Zeitpunkt, zu dem die Werte gelesen wurden.
    public let updatedAt: Date

    public init(
        today: DailyActivitySummary,
        yesterday: DailyActivitySummary,
        currentWeek: ActivityPeriodSummary,
        lastSevenDays: ActivityPeriodSummary,
        updatedAt: Date
    ) {
        self.today = today
        self.yesterday = yesterday
        self.currentWeek = currentWeek
        self.lastSevenDays = lastSevenDays
        self.updatedAt = updatedAt
    }

    /// Tageswert für einen der geladenen Tage (letzte 7 Tage).
    public func summary(for day: LocalDate) -> DailyActivitySummary? {
        lastSevenDays.days.first { $0.date == day }
    }

    /// Werte für einen Zeitraum.
    public func summary(for period: ActivityPeriod) -> ActivityPeriodSummary {
        switch period {
        case .today: ActivityPeriodSummary(period: .today, days: [today])
        case .yesterday: ActivityPeriodSummary(period: .yesterday, days: [yesterday])
        case .currentWeek: currentWeek
        case .lastSevenDays: lastSevenDays
        }
    }
}
