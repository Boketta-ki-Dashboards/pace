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

/// Monatskalender mit erreichten Tageszielen (Referenzbild 9) und der Karte des ausgewählten Tages.
///
/// - Tageswerte kommen aus dem geteilten Verlauf (`ActivityHistoryStore`, 12 Monate, live ergänzt um die letzten
///   7 Tage) – dieselbe Grundlage wie Streak und Statistik. Der Kalender liest nichts zusätzlich aus Apple Health.
/// - Bewertet wird mit dem Ziel des jeweiligen Tages (Zielverlauf).
/// - Zurückblättern bis zum Anfang des Verlaufs, vorwärts bis zum aktuellen Monat.
@MainActor
@Observable
public final class CalendarViewModel {
    public enum Content: Equatable {
        case loading
        case noReadAccess
        case failed(message: String)
        case month(CalendarMonth)
    }

    public let route: CalendarRoute
    /// Erster Tag des angezeigten Monats.
    public private(set) var displayedMonth: LocalDate
    public private(set) var selectedDate: LocalDate

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

        let today = calendar.day(containing: now())
        let month = calendar.startOfMonth(containing: min(route.month ?? today, today))
        displayedMonth = month
        selectedDate = Self.defaultSelection(in: month, today: today, calendar: calendar)
    }

    private var today: LocalDate { calendar.day(containing: now()) }

    /// Frühester Monat mit Verlauf (12 volle Monate vor dem aktuellen).
    public var firstMonth: LocalDate {
        streak.history.firstDay(today: today)
    }

    public var content: Content {
        guard let history = streak.history.history else {
            switch streak.history.state {
            case .noReadAccess: return .noReadAccess
            case .failed(let message): return .failed(message: message)
            case .idle, .loading, .loaded: return .loading
            }
        }
        return .month(CalendarMonth.make(CalendarMonth.Input(
            month: displayedMonth,
            selected: selectedDate,
            history: history,
            goals: streak.goals.history,
            today: today,
            firstMonth: firstMonth,
            formatter: formatter,
            calendar: calendar
        )))
    }

    /// Der ausgewählte Tag mit Schritten und Ziel; `nil`, solange nichts geladen ist.
    public var selectedDay: CalendarDay? {
        guard case .month(let month) = content else { return nil }
        return month.days.first { $0.isSelected }
    }

    public var canShowPrevious: Bool {
        displayedMonth > calendar.startOfMonth(containing: firstMonth)
    }

    public var canShowNext: Bool {
        displayedMonth < calendar.startOfMonth(containing: today)
    }

    /// `Oktober 2026` – auch während des Ladens.
    public var monthTitle: String {
        formatter.monthYear(displayedMonth)
    }

    public func showPrevious() {
        guard canShowPrevious else { return }
        show(month: calendar.addingMonths(-1, to: displayedMonth))
    }

    public func showNext() {
        guard canShowNext else { return }
        show(month: calendar.addingMonths(1, to: displayedMonth))
    }

    /// Wählt einen Tag im angezeigten Monat; die Zukunft lässt sich nicht auswählen.
    public func select(_ day: LocalDate) {
        guard day <= today, calendar.startOfMonth(containing: day) == displayedMonth else { return }
        selectedDate = day
    }

    /// Tagesdetails des Tages (aus dem Kalender geöffnet).
    public func dayDetails(for day: LocalDate) -> DayDetailsViewModel {
        DayDetailsViewModel(
            day: day,
            origin: .calendar,
            streak: streak,
            activityData: activityData,
            live: live,
            calendar: calendar,
            formatter: formatter,
            now: now
        )
    }

    /// Beim Erscheinen: Verlauf laden, falls nötig (geteilter Ladevorgang mit Home und Statistik).
    public func loadIfNeeded() async {
        await streak.loadIfNeeded()
    }

    /// Pull-to-Refresh: heutige Werte und Verlauf neu lesen (spät synchronisierte Werte, z. B. der Apple Watch).
    public func refresh() async {
        await live.refresh()
        await streak.history.reload()
        streak.saveRecordIfNeeded()
    }

    private func show(month: LocalDate) {
        displayedMonth = calendar.startOfMonth(containing: month)
        selectedDate = Self.defaultSelection(in: displayedMonth, today: today, calendar: calendar)
    }

    /// Im aktuellen Monat heute, in früheren Monaten der letzte Tag.
    static func defaultSelection(in month: LocalDate, today: LocalDate, calendar: ActivityCalendar) -> LocalDate {
        min(calendar.endOfMonth(containing: month), today)
    }
}
