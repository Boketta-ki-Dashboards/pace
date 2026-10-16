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

    /// Die zuletzt geladenen Werte, auch während eines erneuten Ladevorgangs.
    public var overview: ActivityOverview? {
        guard case .loaded(let overview) = state else { return nil }
        return overview
    }

    @ObservationIgnored private let loader: ActivitySummaryLoader
    @ObservationIgnored private let activityData: any ActivityDataProviding
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var needsReload = false

    public init(
        activityData: any ActivityDataProviding,
        calendar: ActivityCalendar = ActivityCalendar(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.activityData = activityData
        loader = ActivitySummaryLoader(provider: activityData, calendar: calendar, now: now)
    }

    /// Erstes Laden beim Erscheinen des Screens. Bereits geladene Daten bleiben sichtbar.
    public func loadIfNeeded() async {
        guard case .loading = state else { return }
        await refresh()
    }

    /// Zeigt den Ladezustand und lädt neu – für „Erneut versuchen“ nach Fehlern oder fehlendem Zugriff.
    public func retry() async {
        state = .loading
        await refresh()
    }

    /// Aktualisiert die Werte, ohne die aktuelle Anzeige vorher zu verwerfen.
    ///
    /// Trifft eine Anfrage ein, während noch geladen wird, wird danach genau einmal erneut geladen,
    /// damit keine Änderung verloren geht.
    public func refresh() async {
        guard !isLoading else {
            needsReload = true
            return
        }
        isLoading = true
        defer { isLoading = false }

        repeat {
            needsReload = false
            await performLoad()
        } while needsReload && !Task.isCancelled
    }

    /// Lädt neu, sobald HealthKit neue Bewegungsdaten meldet. Läuft, bis der aufrufende Task beendet wird.
    public func observeActivityChanges() async {
        for await _ in activityData.activityChanges() {
            await refresh()
        }
    }

    private func performLoad() async {
        do {
            switch try await loader.load() {
            case .available(let overview):
                state = .loaded(overview)
            case .noReadAccess:
                state = .noReadAccess
            }
        } catch is CancellationError {
            // Der Screen wurde verlassen; bisherigen Zustand beibehalten.
        } catch {
            state = .failed(message: Self.message(for: error))
        }
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
