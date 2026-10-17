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
        return ActivityStatsViewModel.manualStepsNote
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
            return .unavailable(message: "Pace hat keinen Zugriff auf deine Schritte. Prüfe den Zugriff in der Health-App.")
        }
    }

    /// Zuletzt erfolgreich geladene Werte (für die Detailansicht).
    private var lastLoadedOverview: ActivityOverview?

    @ObservationIgnored private let loader: ActivitySummaryLoader
    @ObservationIgnored private let activityData: any ActivityDataProviding
    @ObservationIgnored private let syncing: (any ActivitySyncing)?
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var needsReload = false
    @ObservationIgnored private var pendingTrigger: ActivitySyncTrigger?

    /// - Parameter syncing: Nimmt neue Tageswerte für das Backend entgegen. `nil`, wenn kein Backend verfügbar ist.
    public init(
        activityData: any ActivityDataProviding,
        syncing: (any ActivitySyncing)? = nil,
        calendar: ActivityCalendar = ActivityCalendar(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.activityData = activityData
        self.syncing = syncing
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

    /// Aktualisiert die Werte, ohne die aktuelle Anzeige vorher zu verwerfen.
    ///
    /// Trifft eine Anfrage ein, während noch geladen wird, wird danach genau einmal erneut geladen,
    /// damit keine Änderung verloren geht.
    public func refresh(trigger: ActivitySyncTrigger) async {
        guard !isLoading else {
            needsReload = true
            pendingTrigger = Self.prioritized(pendingTrigger, trigger)
            return
        }
        isLoading = true
        defer { isLoading = false }

        var currentTrigger = trigger
        repeat {
            needsReload = false
            await performLoad(trigger: currentTrigger)
            currentTrigger = pendingTrigger ?? .healthKitUpdate
            pendingTrigger = nil
        } while needsReload && !Task.isCancelled
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
        Task { [syncing] in
            await syncing.submit(overview, trigger: trigger)
        }
    }

    /// Ein gedrosselter HealthKit-Anlass soll einen sofortigen Anlass (z. B. Pull-to-Refresh) nicht überschreiben.
    private static func prioritized(_ current: ActivitySyncTrigger?, _ new: ActivitySyncTrigger) -> ActivitySyncTrigger {
        guard let current, current != .healthKitUpdate else { return new }
        return current
    }

    static func message(for error: Error) -> String {
        switch error as? HealthDataError {
        case .healthDataUnavailable:
            "Apple Health ist auf diesem Gerät nicht verfügbar."
        case .protectedDataUnavailable:
            "Deine Health-Daten sind geschützt, solange dein iPhone gesperrt ist. Entsperre es und versuche es erneut."
        default:
            "Deine Schritte konnten nicht geladen werden. Bitte versuche es erneut."
        }
    }
}
