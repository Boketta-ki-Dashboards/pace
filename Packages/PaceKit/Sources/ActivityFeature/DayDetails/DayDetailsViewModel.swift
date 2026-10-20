import Foundation
import Observation
import PaceCore

/// Tagesdetails (Referenzbild 8) für einen Tag – aus dem Kalender oder aus der Tagesansicht der Statistik.
///
/// Tageswerte, Ziele und Streak kommen aus dem geteilten Verlauf (`StepStreakTracker`), wie in Kalender und Statistik.
/// Zusätzlich werden die Stundenwerte des Tages gelesen und – nur nach ausdrücklicher Freigabe – Ruhepuls und Ø Puls
/// beim Gehen. Herzwerte bleiben auf dem Gerät.
@MainActor
@Observable
public final class DayDetailsViewModel {
    /// Von wo die Tagesdetails geöffnet wurden (bestimmt den Zurück-Link).
    public enum Origin: Sendable {
        case calendar
        case statistics
    }

    public enum Content: Equatable {
        case loading
        case noReadAccess
        case failed(message: String)
        case report(DayDetailsReport)
    }

    /// Ändert sich, wenn die Stundenwerte neu gelesen werden müssen (heute: bei jeder Änderung der Schritte).
    public struct HourlyKey: Hashable, Sendable {
        let day: LocalDate
        let liveSteps: Int?
    }

    public let day: LocalDate
    public let origin: Origin
    public let streak: StepStreakTracker

    public private(set) var hourly: [Int: Double]?
    public private(set) var hourlyFailed = false
    public private(set) var heartRateAccess: HeartRateAccess = .unavailable
    public private(set) var heartRate: DailyHeartRate?
    public private(set) var isRequestingHeartRate = false
    public private(set) var heartRateRequestFailed = false
    /// In dieser Ansicht wurde gerade nach den Herzwerten gefragt (dann erklärt ein Hinweis, falls keine kommen).
    public private(set) var didRequestHeartRate = false

    @ObservationIgnored private let activityData: any ActivityDataProviding
    @ObservationIgnored private let live: any ActivityOverviewSource
    @ObservationIgnored private let calendar: ActivityCalendar
    @ObservationIgnored private let formatter: ActivityFormatter
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var loadedHourlyKey: HourlyKey?

    public init(
        day: LocalDate,
        origin: Origin = .calendar,
        streak: StepStreakTracker,
        activityData: any ActivityDataProviding,
        live: any ActivityOverviewSource,
        calendar: ActivityCalendar = ActivityCalendar(),
        formatter: ActivityFormatter = ActivityFormatter(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let today = calendar.day(containing: now())
        self.day = min(day, today)
        self.origin = origin
        self.streak = streak
        self.activityData = activityData
        self.live = live
        self.calendar = calendar
        self.formatter = formatter
        self.now = now
    }

    /// `Kalender` bzw. `Statistik` – in der aktuellen Sprache.
    public var backTitle: String {
        switch origin {
        case .calendar: PaceLocalization.text(de: "Kalender", en: "Calendar", ru: "Календарь")
        case .statistics: PaceLocalization.text(de: "Statistik", en: "Statistics", ru: "Статистика")
        }
    }

    private var today: LocalDate { calendar.day(containing: now()) }

    public var content: Content {
        guard let history = streak.history.history else {
            switch streak.history.state {
            case .noReadAccess: return .noReadAccess
            case .failed(let message): return .failed(message: message)
            case .idle, .loading, .loaded: return .loading
            }
        }
        let currentDate = now()
        return .report(DayDetailsReport.make(DayDetailsReport.Input(
            day: day,
            today: calendar.day(containing: currentDate),
            history: history,
            goals: streak.goals.history,
            record: streak.record,
            hourly: hourly,
            hourlyFailed: hourlyFailed,
            currentHour: calendar.calendar.component(.hour, from: currentDate),
            heartRate: heartRateAccess == .unavailable ? nil : heartRate,
            formatter: formatter,
            calendar: calendar
        )))
    }

    /// Angebot „Puls aus Apple Health anzeigen“: nur, solange noch nicht danach gefragt wurde.
    public var offersHeartRate: Bool {
        heartRateAccess == .notRequested
    }

    /// Nach der Freigabe kamen für diesen Tag keine Werte (keine Messung oder keine Zustimmung).
    public var showsNoHeartRateNote: Bool {
        didRequestHeartRate && heartRateAccess == .requested && heartRate?.hasValues != true
    }

    public var hourlyKey: HourlyKey {
        HourlyKey(day: day, liveSteps: day == today ? live.currentOverview?.today.competitionSteps : nil)
    }

    /// Beim Erscheinen: Verlauf (falls nötig) und Herzwerte laden.
    public func loadIfNeeded() async {
        await streak.loadIfNeeded()
        await loadHeartRate()
    }

    /// Pull-to-Refresh: heutige Werte, Verlauf, Stundenwerte und Herzwerte neu lesen.
    public func refresh() async {
        await live.refresh()
        await streak.history.reload()
        streak.saveRecordIfNeeded()
        loadedHourlyKey = nil
        await loadHourly()
        await loadHeartRate()
    }

    /// Liest die Wettbewerbsschritte je Stunde – einmal je Tag, für heute erneut bei neuen Schritten.
    public func loadHourly() async {
        let key = hourlyKey
        guard key != loadedHourlyKey else { return }
        hourlyFailed = false
        do {
            let values = try await activityData.hourlyTotals(of: .competitionSteps, on: key.day, calendar: calendar)
            guard hourlyKey == key else { return }
            hourly = values
            loadedHourlyKey = key
        } catch is CancellationError {
            return
        } catch {
            guard hourlyKey == key else { return }
            // Bereits angezeigte Balken bleiben stehen; nur ohne Werte erscheint der Fehler.
            if hourly == nil { hourlyFailed = true }
        }
    }

    /// Fragt – nur auf Wunsch – nach dem Lesezugriff auf Ruhepuls und Puls beim Gehen und lädt danach die Werte.
    public func requestHeartRateAccess() async {
        guard !isRequestingHeartRate else { return }
        isRequestingHeartRate = true
        heartRateRequestFailed = false
        defer { isRequestingHeartRate = false }
        do {
            try await activityData.requestHeartRateAccess()
            didRequestHeartRate = true
        } catch {
            heartRateRequestFailed = true
        }
        await loadHeartRate()
    }

    private func loadHeartRate() async {
        heartRateAccess = await activityData.heartRateAccess()
        guard heartRateAccess == .requested else {
            heartRate = nil
            return
        }
        do {
            heartRate = try await activityData.dailyHeartRate(on: day, calendar: calendar)
        } catch is CancellationError {
            return
        } catch {
            // Herzwerte sind optional: Ohne lesbare Werte erscheinen die Kacheln einfach nicht.
            heartRate = nil
        }
    }
}
