import Foundation
import Observation
import PaceCore

/// Bewegungsverlauf der letzten 12 Monate für Statistiken, Bestwerte und Streak – geteilt von allen Ansichten.
///
/// - Der Verlauf wird selten gelesen: beim ersten Bedarf, nach einem Tageswechsel und wenn er älter als
///   `maximumAge` ist (spät synchronisierte Werte, z. B. von der Apple Watch). Eine Abfrage pro Kennzahl.
/// - Die letzten 7 Tage kommen dagegen live aus `live` (Home), damit heute immer aktuell ist, ohne dass der ganze
///   Verlauf bei jeder Schrittänderung neu gelesen wird.
/// - Gleichzeitige Anfragen teilen sich einen Ladevorgang.
@MainActor
@Observable
public final class ActivityHistoryStore {
    public enum State: Equatable, Sendable {
        case idle
        case loading
        case loaded
        /// Keine Schrittdaten lesbar.
        case noReadAccess
        /// Laden fehlgeschlagen; ein früher geladener Verlauf bleibt verfügbar.
        case failed(message: String)
    }

    /// Wie viele volle Monate vor dem aktuellen Monat geladen werden.
    public static let monthsOfHistory = 12

    public private(set) var state: State = .idle
    private var loaded: ActivityHistory?

    @ObservationIgnored private let loader: ActivitySummaryLoader
    @ObservationIgnored private let live: any ActivityOverviewSource
    @ObservationIgnored private let calendar: ActivityCalendar
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let maximumAge: TimeInterval
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var lastAttempt: Date?

    public init(
        activityData: any ActivityDataProviding,
        live: any ActivityOverviewSource,
        calendar: ActivityCalendar = ActivityCalendar(),
        maximumAge: TimeInterval = 3_600,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        loader = ActivitySummaryLoader(provider: activityData, calendar: calendar, now: now)
        self.live = live
        self.calendar = calendar
        self.maximumAge = maximumAge
        self.now = now
    }

    /// Verlauf inklusive der live aktualisierten letzten 7 Tage; `nil`, solange nichts geladen ist.
    public var history: ActivityHistory? {
        guard let loaded else { return nil }
        guard let overview = live.currentOverview else { return loaded }
        return loaded.merging(overview.lastSevenDays.days)
    }

    /// Erster Tag, den der Verlauf abdeckt (Monatsanfang vor 12 Monaten).
    public func firstDay(today: LocalDate) -> LocalDate {
        calendar.addingMonths(-Self.monthsOfHistory, to: calendar.startOfMonth(containing: today))
    }

    /// Lädt, falls noch nichts geladen ist, seit dem Laden ein neuer Tag begonnen hat oder der Stand zu alt ist.
    public func loadIfNeeded() async {
        if let loadTask {
            await loadTask.value
            return
        }
        if let loaded, !isStale(loaded) { return }
        // Ohne Verlauf (kein Lesezugriff, Fehler) nicht bei jedem Erscheinen einer Ansicht erneut abfragen.
        if loaded == nil, let lastAttempt, now().timeIntervalSince(lastAttempt) < 60 { return }
        await reload()
    }

    /// Lädt neu (z. B. Pull-to-Refresh). Läuft schon ein Ladevorgang, wartet der Aufrufer auf ihn.
    public func reload() async {
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { await self.performLoad() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad() async {
        lastAttempt = now()
        if loaded == nil {
            state = .loading
        }
        let today = calendar.day(containing: now())
        do {
            switch try await loader.loadHistory(from: firstDay(today: today)) {
            case .available(let history):
                loaded = history
                state = .loaded
            case .noReadAccess:
                loaded = nil
                state = .noReadAccess
            }
        } catch is CancellationError {
            if loaded == nil { state = .idle }
        } catch {
            state = .failed(message: "Der Verlauf konnte nicht geladen werden. Bitte versuche es erneut.")
        }
    }

    private func isStale(_ history: ActivityHistory) -> Bool {
        let currentDate = now()
        return calendar.day(containing: history.updatedAt) != calendar.day(containing: currentDate)
            || currentDate.timeIntervalSince(history.updatedAt) > maximumAge
    }
}
