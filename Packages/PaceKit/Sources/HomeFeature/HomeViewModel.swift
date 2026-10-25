import ActivityFeature
import Foundation
import Observation
import PaceCore

/// Lädt und aktualisiert die Bewegungsdaten für den Home-Screen.
@MainActor
@Observable
public final class HomeViewModel {
    public enum State: Equatable {
        case loading
        case loaded(ActivityOverview)
        /// Es sind keine Schrittdaten lesbar – meist, weil der Lesezugriff verweigert wurde.
        case noReadAccess
        case failed(message: String)
    }

    public private(set) var state: State = .loading

    /// Die aktuell angezeigten Werte; `nil` während des Ladens, bei Fehlern und ohne Lesezugriff.
    public var overview: ActivityOverview? {
        guard case .loaded(let overview) = state else { return nil }
        return overview
    }

    /// Hinweis unter der Schrittzahl, wenn heute Schritte in Apple Health nicht für Rankings zählen.
    public var manualStepsNote: String? {
        guard let overview, overview.today.hasNonCompetitionSteps else { return nil }
        return HomeTexts.manualStepsNote
    }

    /// Zustand der Detailansicht. Scheitert eine spätere Aktualisierung, bleiben die zuletzt geladenen Werte mit
    /// Hinweis sichtbar, statt dass die Ansicht leer wird.
    public var detailsState: ActivityDetailsState {
        switch state {
        case .loaded(let overview):
            return .loaded(overview, notice: nil)
        case .loading:
            return lastLoadedOverview.map { .loaded($0, notice: nil) } ?? .loading
        case .failed(let message):
            return lastLoadedOverview.map { .loaded($0, notice: message) } ?? .unavailable(message: message)
        case .noReadAccess:
            return .unavailable(message: PaceLocalization.text(
                de: "Pace hat keinen Zugriff auf deine Schritte. Prüfe den Zugriff in der Health-App.",
                en: "Pace can't access your steps. Check the access in the Health app.",
                ru: "У Pace нет доступа к твоим шагам. Проверь доступ в приложении «Здоровье»."
            ))
        }
    }

    /// Zuletzt erfolgreich geladene Werte (für die Detailansicht).
    private var lastLoadedOverview: ActivityOverview?

    /// Abgleich der HealthKit-Werte mit den schnelleren Sensorwerten (nur für die Anzeige).
    private var liveEstimator = LiveStepEstimator()

    /// Protokoll des Live-Abgleichs – nur für die Diagnose in Entwicklungs-Builds (begrenzt, nie hochgeladen).
    public let liveDiagnostics = LiveStepDiagnostics()

    /// Wettbewerbsschritte von heute für die Anzeige – mit Live-Sensorwerten, solange Pace im Vordergrund ist.
    /// Rankings, Sync, Serie und Mitteilungen verwenden weiter nur die HealthKit-Werte aus ``overview``.
    public var liveCompetitionStepsToday: Int? {
        guard let overview, liveEstimator.day == overview.today.date else { return overview?.today.competitionSteps }
        return max(liveEstimator.steps, overview.today.competitionSteps)
    }

    @ObservationIgnored private let loader: ActivitySummaryLoader
    @ObservationIgnored private let activityData: any ActivityDataProviding
    @ObservationIgnored private let syncing: (any ActivitySyncing)?
    @ObservationIgnored private let liveSteps: any LiveStepCounting
    @ObservationIgnored private let calendar: ActivityCalendar
    @ObservationIgnored private let now: @Sendable () -> Date
    /// Der laufende Ladevorgang. Läuft unabhängig vom Aufrufer, damit ein abgebrochener Aufrufer (z. B. ein
    /// beendeter `.task`) weder die HealthKit-Abfrage abbricht noch nachgemeldete Anfragen verliert.
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var needsReload = false
    @ObservationIgnored private var pendingTrigger: ActivitySyncTrigger?
    /// Letzte Übergabe an den Sync. Übergaben laufen nacheinander, damit `refreshForRanking()` auf sie warten kann.
    @ObservationIgnored private var lastSubmission: Task<Void, Never>?

    /// - Parameters:
    ///   - syncing: Nimmt neue Tageswerte für das Backend entgegen. `nil`, wenn kein Backend verfügbar ist.
    ///   - liveSteps: Schnelle Sensorwerte für die Anzeige im Vordergrund (Core Motion).
    public init(
        activityData: any ActivityDataProviding,
        syncing: (any ActivitySyncing)? = nil,
        liveSteps: any LiveStepCounting = NoLiveStepCounting(),
        calendar: ActivityCalendar = ActivityCalendar(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.activityData = activityData
        self.syncing = syncing
        self.liveSteps = liveSteps
        self.calendar = calendar
        self.now = now
        loader = ActivitySummaryLoader(provider: activityData, calendar: calendar, now: now)
    }

    /// Erstes Laden beim Erscheinen des Screens (App-Start). Bereits geladene Daten bleiben sichtbar.
    public func loadIfNeeded() async {
        guard case .loading = state else { return }
        await refresh(trigger: .appStart)
    }

    /// Zeigt den Ladezustand und lädt neu – für „Erneut versuchen“ nach Fehlern oder fehlendem Zugriff.
    public func retry() async {
        state = .loading
        await refresh(trigger: .pullToRefresh)
    }

    /// Aktualisiert die Werte per Pull-to-Refresh.
    public func refresh() async {
        await refresh(trigger: .pullToRefresh)
    }

    /// Aktualisiert die Werte, ohne die aktuelle Anzeige vorher zu verwerfen. Kehrt zurück, wenn geladen wurde.
    ///
    /// Trifft eine Anfrage ein, während noch geladen wird, wird danach genau einmal erneut geladen,
    /// damit keine Änderung verloren geht; der Aufrufer wartet bis dahin.
    public func refresh(trigger: ActivitySyncTrigger) async {
        if let loadTask {
            needsReload = true
            pendingTrigger = Self.prioritized(pendingTrigger, trigger)
            await loadTask.value
            return
        }
        let task = Task { await self.runLoads(startingWith: trigger) }
        loadTask = task
        await task.value
    }

    private func runLoads(startingWith trigger: ActivitySyncTrigger) async {
        var currentTrigger = trigger
        repeat {
            needsReload = false
            await performLoad(trigger: currentTrigger)
            currentTrigger = pendingTrigger ?? .healthKitUpdate
            pendingTrigger = nil
        } while needsReload
        loadTask = nil
    }

    /// Wartet, bis ein laufender Ladevorgang abgeschlossen ist (ohne auf den Sync zu warten).
    public func waitForPendingLoad() async {
        await loadTask?.value
    }

    /// Wartet, bis ein laufender Ladevorgang abgeschlossen und sein Ergebnis an den Sync übergeben ist.
    public func waitForPendingSync() async {
        await loadTask?.value
        await lastSubmission?.value
    }

    /// Live-Schritte vom Bewegungssensor, solange der aufrufende Task läuft (Pace im Vordergrund). Ohne Zugriff
    /// oder Sensor endet die Methode sofort; die Anzeige folgt dann nur HealthKit.
    ///
    /// Gemessen wird ab Tagesbeginn. Nach Mitternacht beginnt die Messung mit dem ersten Wert des neuen Tages neu
    /// (Werte, die noch ab dem Vortag zählen, werden verworfen).
    public func observeLiveSteps() async {
        let status = liveSteps.status
        guard status.canCount else {
            liveDiagnostics.record(.unavailable, at: now(), status: status, estimator: liveEstimator)
            return
        }
        while !Task.isCancelled {
            let day = calendar.day(containing: now())
            let start = calendar.startOfDay(day)
            liveDiagnostics.record(.started, at: now(), status: status, estimator: liveEstimator, start: start)
            var reachedNextDay = false
            for await reading in liveSteps.readings(since: start) {
                let readingDay = calendar.day(containing: reading.date)
                if readingDay > day {
                    reachedNextDay = true
                    break
                }
                guard readingDay == day else { continue }
                let previous = liveEstimator.latestSensor
                liveEstimator.sensor(reading.steps, on: day, at: reading.date)
                if let previous, reading.steps < previous {
                    liveDiagnostics.record(.sensorRestarted, value: reading.steps, at: reading.date, status: status, estimator: liveEstimator)
                }
                liveDiagnostics.record(.sensor, value: reading.steps, at: reading.date, status: status, estimator: liveEstimator)
            }
            liveEstimator.sensorStopped()
            guard reachedNextDay, !Task.isCancelled else { break }
            liveDiagnostics.record(.dayChanged, at: now(), status: status, estimator: liveEstimator)
        }
        liveDiagnostics.record(.stopped, at: now(), status: liveSteps.status, estimator: liveEstimator)
    }

    /// Lädt neu, sobald HealthKit neue Bewegungsdaten meldet. Läuft, bis der aufrufende Task beendet wird.
    public func observeActivityChanges() async {
        for await _ in activityData.activityChanges() {
            await refresh(trigger: .healthKitUpdate)
        }
    }

    private func performLoad(trigger: ActivitySyncTrigger) async {
        do {
            switch try await loader.load() {
            case .available(let overview):
                var estimator = liveEstimator
                estimator.healthKit(overview.today.competitionSteps, on: overview.today.date)
                if estimator != liveEstimator {
                    liveDiagnostics.record(
                        .healthKit, value: overview.today.competitionSteps, at: now(), status: liveSteps.status, estimator: estimator
                    )
                }
                // Unbestätigte Schritte, die HealthKit 20 Minuten nach dem letzten Sensor-Fortschritt nicht kennt, verfallen.
                if estimator.settle(at: now()) {
                    liveDiagnostics.record(
                        .unconfirmedExpired, value: overview.today.competitionSteps, at: now(), status: liveSteps.status, estimator: estimator
                    )
                }
                if estimator != liveEstimator {
                    liveEstimator = estimator
                }
                // Unveränderte Werte (häufig bei der Abfrage im Vordergrund) lösen kein Neuzeichnen aus.
                if case .loaded(let current) = state, Self.hasSameValues(current, overview) {
                    submitForSync(current, trigger: trigger)
                    return
                }
                state = .loaded(overview)
                lastLoadedOverview = overview
                submitForSync(overview, trigger: trigger)
            case .noReadAccess:
                state = .noReadAccess
            }
        } catch is CancellationError {
            // Der Screen wurde verlassen; bisherigen Zustand beibehalten.
        } catch {
            state = .failed(message: Self.message(for: error))
        }
    }

    /// Übergibt die Werte an den Sync, ohne die Anzeige zu blockieren. Fehler behandelt der Sync selbst.
    private func submitForSync(_ overview: ActivityOverview, trigger: ActivitySyncTrigger) {
        guard let syncing else { return }
        lastSubmission = Task { [syncing, previous = lastSubmission] in
            await previous?.value
            await syncing.submit(overview, trigger: trigger)
        }
    }

    /// Für Pull-to-Refresh in den Rankings: liest die Werte neu aus Apple Health und wartet, bis sie an den Sync
    /// übergeben sind – danach kann das Ranking mit dem eigenen aktuellen Stand geladen werden.
    public func refreshForRanking() async {
        await refresh(trigger: .pullToRefresh)
        await lastSubmission?.value
    }

    /// Gleiche Werte, nur ein anderer Lesezeitpunkt.
    private static func hasSameValues(_ lhs: ActivityOverview, _ rhs: ActivityOverview) -> Bool {
        lhs.today == rhs.today
            && lhs.yesterday == rhs.yesterday
            && lhs.currentWeek == rhs.currentWeek
            && lhs.lastSevenDays == rhs.lastSevenDays
    }

    /// Ein gedrosselter HealthKit-Anlass soll einen sofortigen Anlass (z. B. Pull-to-Refresh) nicht überschreiben.
    private static func prioritized(_ current: ActivitySyncTrigger?, _ new: ActivitySyncTrigger) -> ActivitySyncTrigger {
        guard let current, current != .healthKitUpdate else { return new }
        return current
    }

    static func message(for error: Error) -> String {
        switch error as? HealthDataError {
        case .healthDataUnavailable:
            PaceLocalization.text(
                de: "Apple Health ist auf diesem Gerät nicht verfügbar.",
                en: "Apple Health isn't available on this device.",
                ru: "Apple Health недоступно на этом устройстве."
            )
        case .protectedDataUnavailable:
            PaceLocalization.text(
                de: "Deine Health-Daten sind geschützt, solange dein iPhone gesperrt ist. Entsperre es und versuche es erneut.",
                en: "Your health data is protected while your iPhone is locked. Unlock it and try again.",
                ru: "Данные о здоровье защищены, пока iPhone заблокирован. Разблокируй его и попробуй снова."
            )
        default:
            PaceLocalization.text(
                de: "Deine Schritte konnten nicht geladen werden. Bitte versuche es erneut.",
                en: "Your steps couldn't be loaded. Please try again.",
                ru: "Не удалось загрузить шаги. Попробуй ещё раз."
            )
        }
    }
}
