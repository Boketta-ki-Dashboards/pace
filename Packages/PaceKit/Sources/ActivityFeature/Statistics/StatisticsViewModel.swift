import Foundation
import Observation
import PaceCore

/// Ziel einer Navigation in die Statistik, z. B. „Distanz der Woche“ oder „ein bestimmter Tag“.
public struct StatisticsRoute: Hashable, Sendable {
    public let period: StatisticsPeriod
    public let metric: StatisticsMetric
    /// Angezeigter Tag bzw. ein Tag im angezeigten Zeitraum; `nil` = heute.
    public let day: LocalDate?

    public init(period: StatisticsPeriod, metric: StatisticsMetric = .steps, day: LocalDate? = nil) {
        self.period = period
        self.metric = metric
        self.day = day
    }
}

/// Statistik für Tag, Woche und Monat mit Navigation zwischen Zeiträumen.
///
/// Tageswerte kommen aus dem geteilten Verlauf (`ActivityHistoryStore`, live ergänzt um die letzten 7 Tage).
/// Nur für das Tagesdiagramm werden Stundenwerte gelesen – je Tag und Kennzahl einmal; für heute erneut, sobald sich
/// der Tageswert ändert.
@MainActor
@Observable
public final class StatisticsViewModel {
    public enum Content: Equatable {
        case loading
        case noReadAccess
        case failed(message: String)
        case report(StatisticsReport)
    }

    public enum HourlyState: Equatable {
        case idle
        case loading
        case loaded(HourlyValues)
        case failed
    }

    /// Ändert sich, wenn Stundenwerte (neu) geladen werden müssen.
    public struct HourlyKey: Hashable, Sendable {
        let day: LocalDate
        let metric: StatisticsMetric
        /// Aktueller Tageswert für heute (neu laden bei Änderung); `nil` für vergangene Tage.
        let liveValue: Double?
    }

    public private(set) var period: StatisticsPeriod
    public private(set) var metric: StatisticsMetric
    public private(set) var anchor: LocalDate
    public private(set) var hourly: HourlyState = .idle

    public let streak: StepStreakTracker

    @ObservationIgnored private let activityData: any ActivityDataProviding
    @ObservationIgnored private let live: any ActivityOverviewSource
    @ObservationIgnored private let calendar: ActivityCalendar
    @ObservationIgnored private let formatter: ActivityFormatter
    @ObservationIgnored private let now: @Sendable () -> Date
    /// Stundenwerte vergangener Tage ändern sich praktisch nicht mehr und werden wiederverwendet.
    @ObservationIgnored private var hourlyCache: [HourlyKey: HourlyValues] = [:]

    public init(
        route: StatisticsRoute,
        streak: StepStreakTracker,
        activityData: any ActivityDataProviding,
        live: any ActivityOverviewSource,
        calendar: ActivityCalendar = ActivityCalendar(),
        formatter: ActivityFormatter = ActivityFormatter(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.streak = streak
        self.activityData = activityData
        self.live = live
        self.calendar = calendar
        self.formatter = formatter
        self.now = now
        period = route.period
        metric = route.metric
        let today = calendar.day(containing: now())
        anchor = min(route.day ?? today, today)
    }

    private var history: ActivityHistoryStore { streak.history }

    private var today: LocalDate { calendar.day(containing: now()) }

    public var content: Content {
        guard let loaded = history.history else {
            switch history.state {
            case .noReadAccess: return .noReadAccess
            case .failed(let message): return .failed(message: message)
            case .idle, .loading, .loaded: return .loading
            }
        }
        let currentDate = now()
        let components = calendar.calendar.dateComponents([.hour, .minute], from: currentDate)
        let report = StatisticsReport.make(StatisticsReport.Input(
            period: period,
            metric: metric,
            anchor: anchor,
            history: loaded,
            goals: streak.goals.history,
            record: streak.record,
            hourly: hourlyValues,
            today: calendar.day(containing: currentDate),
            currentHour: components.hour ?? 0,
            fractionOfCurrentHour: Double(components.minute ?? 0) / 60,
            formatter: formatter,
            calendar: calendar
        ))
        return .report(report)
    }

    public var hourlyValues: HourlyValues? {
        guard case .loaded(let values) = hourly else { return nil }
        return values
    }

    /// Schlüssel für das Laden der Stundenwerte; `nil` außerhalb der Tagesansicht.
    public var hourlyKey: HourlyKey? {
        guard period == .day else { return nil }
        let liveValue = anchor == today ? live.currentOverview.flatMap { metric.value(of: $0.today) } : nil
        return HourlyKey(day: anchor, metric: metric, liveValue: liveValue)
    }

    public func select(_ period: StatisticsPeriod) {
        self.period = period
        anchor = min(anchor, today)
    }

    public func select(_ metric: StatisticsMetric) {
        self.metric = metric
    }

    /// Zeigt einen Tag (z. B. nach Tippen auf einen Balken).
    public func showDay(_ day: LocalDate) {
        guard day <= today else { return }
        period = .day
        anchor = day
    }

    public func showPrevious() {
        guard case .report(let report) = content, report.canShowPrevious else { return }
        anchor = shifted(by: -1)
    }

    public func showNext() {
        guard case .report(let report) = content, report.canShowNext else { return }
        anchor = min(shifted(by: 1), today)
    }

    /// Beim Erscheinen: Verlauf laden, falls nötig.
    public func loadIfNeeded() async {
        await streak.loadIfNeeded()
    }

    /// Pull-to-Refresh: heutige Werte, Verlauf und Stundenwerte neu lesen.
    public func refresh() async {
        await live.refresh()
        await history.reload()
        streak.saveRecordIfNeeded()
        hourlyCache.removeAll()
        await loadHourly()
    }

    /// Lädt die Stundenwerte für den angezeigten Tag (Tagesansicht).
    public func loadHourly() async {
        guard let key = hourlyKey else { return }
        if let cached = hourlyCache[key] {
            hourly = .loaded(cached)
            return
        }
        // Beim Aktualisieren desselben Tages bleiben die bisherigen Balken stehen (kein Flackern).
        if hourlyValues?.day != key.day || hourlyValues?.metric != key.metric {
            hourly = .loading
        }

        let isToday = key.day == today
        do {
            let values = try await activityData.hourlyTotals(of: key.metric.activityMetric, on: key.day, calendar: calendar)
            let previous = isToday
                ? try await activityData.hourlyTotals(
                    of: key.metric.activityMetric,
                    on: calendar.adding(-1, to: key.day),
                    calendar: calendar
                )
                : nil
            // Inzwischen ein anderer Tag oder eine andere Kennzahl gewählt: Ergebnis verwerfen.
            guard hourlyKey == key else { return }
            let result = HourlyValues(day: key.day, metric: key.metric, values: values, previousDay: previous)
            if !isToday {
                hourlyCache[key] = result
            }
            hourly = .loaded(result)
        } catch is CancellationError {
            return
        } catch {
            guard hourlyKey == key else { return }
            hourly = .failed
        }
    }

    private func shifted(by direction: Int) -> LocalDate {
        switch period {
        case .day: calendar.adding(direction, to: anchor)
        case .week: calendar.adding(7 * direction, to: anchor)
        case .month: calendar.addingMonths(direction, to: anchor)
        }
    }
}
