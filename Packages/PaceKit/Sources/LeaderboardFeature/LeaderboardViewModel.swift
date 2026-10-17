import Foundation
import Observation
import PaceCore

/// Tagesrankings für die vier regionalen Ebenen des Nutzers.
///
/// Sortierung, Plätze und Pagination kommen vom Server. Geladen werden die Top-Plätze und – falls der Nutzer nicht
/// darunter ist – seine eigene Position mit den direkten Nachbarn.
@MainActor
@Observable
public final class LeaderboardViewModel {
    public enum State: Equatable {
        case loading
        case loaded(LeaderboardSnapshot)
        case failed(message: String)
    }

    /// Ändert sich, wenn die Rankings neu geladen werden müssen (andere Gemeinde, geänderte Teilnahme).
    public struct ReloadKey: Hashable, Sendable {
        let municipalityID: RegionID?
        let isParticipating: Bool
    }

    public private(set) var state: State = .loading
    /// Zeitraum der Anzeige. Milestone 2 zeigt nur Tagesrankings; das Backend kann auch `weekly`.
    public let period: LeaderboardPeriod = .daily
    public private(set) var isUpdatingParticipation = false
    public private(set) var participationError: String?

    /// Vom Nutzer gewählte Ebene; `nil` bedeutet die Gemeinde.
    private var selectedScopeID: RegionID?

    @ObservationIgnored private let store: ProfileStore
    @ObservationIgnored private let loader: LeaderboardLoader
    @ObservationIgnored private let syncing: (any ActivitySyncing)?
    @ObservationIgnored private let calendar: ActivityCalendar
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let maximumAge: Duration
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var inFlightKey: LoadKey?
    @ObservationIgnored private var loadedKey: LoadKey?
    @ObservationIgnored private var lastLoadedAt: ContinuousClock.Instant?

    /// - Parameters:
    ///   - syncing: Sendet zurückgehaltene Schritte vor dem Laden, damit der eigene Platz aktuell ist.
    ///   - maximumAge: Nach dieser Zeit lädt `loadIfNeeded()` beim nächsten Erscheinen neu.
    public init(
        store: ProfileStore,
        leaderboards: any LeaderboardRepository,
        syncing: (any ActivitySyncing)?,
        calendar: ActivityCalendar = ActivityCalendar(),
        now: @escaping @Sendable () -> Date = { Date() },
        topLimit: Int = 50,
        maximumAge: Duration = .seconds(60)
    ) {
        self.store = store
        self.syncing = syncing
        self.calendar = calendar
        self.now = now
        self.maximumAge = maximumAge
        loader = LeaderboardLoader(repository: leaderboards, topLimit: topLimit, neighborRadius: 1)
    }

    /// Ebenen von klein nach groß, z. B. Pfungstadt, Landkreis Darmstadt-Dieburg, Hessen, Deutschland.
    public var scopes: [Region] {
        store.hierarchy?.leaderboardScopes ?? []
    }

    public var selectedScope: Region? {
        scopes.first { $0.id == selectedScopeID } ?? scopes.first
    }

    public var isParticipating: Bool {
        store.profile.regionalLeaderboardEnabled
    }

    public var reloadKey: ReloadKey {
        ReloadKey(municipalityID: store.profile.municipalityID, isParticipating: isParticipating)
    }

    public var snapshot: LeaderboardSnapshot? {
        guard case .loaded(let snapshot) = state else { return nil }
        return snapshot
    }

    /// Text für ein leeres Ranking bzw. wenn der Nutzer allein darin ist. `nil`, wenn es nichts zu erklären gibt.
    public var emptyStateText: String? {
        guard let snapshot, let region = scopes.first(where: { $0.id == snapshot.query.regionID }) else { return nil }
        let place = Self.locative(region)
        if snapshot.isCurrentUserAlone {
            return "Du bist der Erste \(place)."
        }
        if snapshot.isEmpty {
            return isParticipating
                ? "Heute hat \(place) noch niemand Schritte gesammelt. Deine erscheinen, sobald sie synchronisiert sind."
                : "Heute tritt \(place) noch niemand an."
        }
        return nil
    }

    /// Ortsangabe mit passender Präposition: „in Pfungstadt“, „im Landkreis Darmstadt-Dieburg“, „im Saarland“.
    static func locative(_ region: Region) -> String {
        switch region.kind {
        case .landkreis, .kreis, .stadtkreis:
            return "im \(region.displayName)"
        case .regionalverband:
            return "im Regionalverband \(region.name)"
        default:
            return region.name == "Saarland" ? "im Saarland" : "in \(region.name)"
        }
    }

    /// Lädt beim Erscheinen – nur wenn sich etwas geändert hat, der letzte Versuch fehlschlug oder die Daten älter
    /// als `maximumAge` sind.
    public func loadIfNeeded() async {
        let key = currentLoadKey
        guard inFlightKey != key else { return }
        if case .loaded = state, loadedKey == key, let lastLoadedAt, ContinuousClock.now - lastLoadedAt < maximumAge {
            return
        }
        await load()
    }

    /// Wechselt die Ebene, z. B. von der Gemeinde zum Bundesland.
    public func select(_ scope: Region) async {
        guard scope.id != selectedScope?.id else { return }
        selectedScopeID = scope.id
        state = .loading
        await load()
    }

    /// Pull-to-Refresh: lädt neu, ohne die aktuelle Anzeige vorher zu verwerfen.
    public func refresh() async {
        await load()
    }

    /// „Erneut versuchen“ nach einem Fehler.
    public func retry() async {
        state = .loading
        await load()
    }

    /// Ausdrückliche Zustimmung, in regionalen Rankings zu erscheinen.
    public func enableParticipation() async {
        guard !isUpdatingParticipation, !isParticipating else { return }
        isUpdatingParticipation = true
        participationError = nil
        defer { isUpdatingParticipation = false }

        do {
            try await store.setRegionalLeaderboardEnabled(true)
        } catch {
            participationError = "Das hat nicht geklappt. Prüfe deine Verbindung und versuche es erneut."
            return
        }
        await load()
    }

    private func load() async {
        generation += 1
        let current = generation
        let key = currentLoadKey
        inFlightKey = key
        defer {
            if current == generation { inFlightKey = nil }
        }
        // Andere Ebene, Gemeinde oder Teilnahme: Das alte Ranking passt nicht mehr und wird nicht weiter angezeigt.
        if let loadedKey, loadedKey != key {
            state = .loading
        }

        do {
            try await store.loadHierarchyIfNeeded()
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            state = .failed(message: Self.message(for: error))
            return
        }
        guard current == generation, !Task.isCancelled else { return }
        guard let scope = selectedScope else {
            state = .failed(message: "Wähle im Profil eine Gemeinde, um Rankings zu sehen.")
            return
        }

        // Eigene Schritte zuerst hochladen, damit der eigene Platz stimmt.
        await syncing?.flush()

        let query = LeaderboardQuery(regionID: scope.id, period: period, date: calendar.day(containing: now()))
        do {
            let snapshot = try await loader.load(query)
            guard current == generation, !Task.isCancelled else { return }
            state = .loaded(snapshot)
            loadedKey = key
            lastLoadedAt = .now
        } catch {
            guard current == generation, !Task.isCancelled, !(error is CancellationError) else { return }
            if case .loaded(let previous) = state, previous.query == query {
                // Pull-to-Refresh ohne Netz: Die alten Werte bleiben sichtbar.
                return
            }
            state = .failed(message: Self.message(for: error))
        }
    }

    private struct LoadKey: Equatable {
        let reloadKey: ReloadKey
        let scopeID: RegionID?
    }

    private var currentLoadKey: LoadKey {
        LoadKey(reloadKey: reloadKey, scopeID: selectedScopeID)
    }

    static func message(for error: Error) -> String {
        if error as? LeaderboardError == .network || error as? RegionError == .network {
            return "Keine Verbindung. Prüfe deine Internetverbindung und versuche es erneut."
        }
        if error as? LeaderboardError == .unknownRegion || error as? RegionError == .notFound {
            return "Deine Region ist nicht mehr verfügbar. Bitte wähle sie im Profil neu."
        }
        return "Das Ranking konnte nicht geladen werden. Bitte versuche es erneut."
    }
}
