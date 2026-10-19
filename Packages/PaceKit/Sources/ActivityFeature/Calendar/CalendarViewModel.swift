import Foundation
import Observation
import PaceCore

/// Navigation zum Kalender (Home → Kalender-Symbol).
public struct CalendarRoute: Hashable, Sendable {
    /// Ein Tag im angezeigten Monat; `nil` = aktueller Monat.
    public let month: LocalDate?

    public init(month: LocalDate? = nil) {
        self.month = month
    }
}

/// Kalender mit erreichten Tageszielen und Tagesdetails.
///
/// Vertrag für Home (Navigation und Erzeugung); Inhalt und Logik entstehen im Kalender-Arbeitspaket.
@MainActor
@Observable
public final class CalendarViewModel {
    public let route: CalendarRoute

    @ObservationIgnored let streak: StepStreakTracker
    @ObservationIgnored let activityData: any ActivityDataProviding
    @ObservationIgnored let live: any ActivityOverviewSource
    @ObservationIgnored let calendar: ActivityCalendar
    @ObservationIgnored let formatter: ActivityFormatter
    @ObservationIgnored let now: @Sendable () -> Date

    public init(
        route: CalendarRoute = CalendarRoute(),
        streak: StepStreakTracker,
        activityData: any ActivityDataProviding,
        live: any ActivityOverviewSource,
        calendar: ActivityCalendar = ActivityCalendar(),
        formatter: ActivityFormatter = ActivityFormatter(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.route = route
        self.streak = streak
        self.activityData = activityData
        self.live = live
        self.calendar = calendar
        self.formatter = formatter
        self.now = now
    }
}
