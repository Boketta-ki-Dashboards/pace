import Foundation
import Observation
import PaceCore

/// Eigene Platzierung in jeder Ranking-Ebene (Gemeinde, Kreis, Bundesland, Land) und das Umfeld in den Ebenen, die
/// Umfeld-Module anzeigen.
///
/// Nutzt dieselben Ranking-RPCs wie der Rankings-Tab (eigene Position ± Nachbarn); es werden nie ganze Rankings
/// geladen.
@MainActor
@Observable
public final class RegionalStandingsViewModel {
    public enum State: Equatable {
        case idle
        case loading
        case loaded(RegionalStandings)
        case failed(message: String)
    }

    public private(set) var state: State = .idle
    public private(set) var isUpdatingParticipation = false
    public private(set) var participationError: String?

    @ObservationIgnored private let store: ProfileStore
    @ObservationIgnored private let leaderboards: any LeaderboardRepository
    @ObservationIgnored private let syncing: (any ActivitySyncing)?
    @ObservationIgnored private let calendar: ActivityCalendar
    @ObservationIgnored private let now: @Sendable () -> Date
    /// Der laufende Ladevorgang; weitere Anfragen warten darauf und lösen höchstens ein erneutes Laden aus.
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var needsReload = false
    /// Beginn des letzten Ladeversuchs – auch fehlgeschlagene Versuche warten so bis zum nächsten.
    @ObservationIgnored private var lastAttemptAt: ContinuousClock.Instant?
    @ObservationIgnored private var loadedKey: ReloadKey?

    public struct ReloadKey: Hashable, Sendable {
        let municipalityID: RegionID?
        let isParticipating: Bool
        let neighborhoodRadii: [RegionLevel: Int]
    }

    /// Plätze über und unter dem eigenen, die je Ebene geladen werden (für Umfeld-Module). Ebenen ohne Eintrag liefern
    /// nur den eigenen Platz.
    public var neighborhoodRadii: [RegionLevel: Int] = [.municipality: 2]

    public init(
        store: ProfileStore,
        leaderboards: any LeaderboardRepository,
        syncing: (any ActivitySyncing)?,
        calendar: ActivityCalendar = ActivityCalendar(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.leaderboards = leaderboards
        self.syncing = syncing
        self.calendar = calendar
        self.now = now
    }

    public var isParticipating: Bool {
        store.profile.regionalLeaderboardEnabled
    }

    public var reloadKey: ReloadKey {
        ReloadKey(
            municipalityID: store.profile.municipalityID,
            isParticipating: isParticipating,
            neighborhoodRadii: neighborhoodRadii
        )
    }

    public var standings: RegionalStandings? {
        guard case .loaded(let standings) = state else { return nil }
        return standings
    }

    /// Ebenen für die Karten, auch bevor Platzierungen geladen sind.
    public var scopes: [Region] {
        store.hierarchy?.leaderboardScopes ?? []
    }

    /// Lädt, wenn noch nichts geladen ist oder sich Gemeinde bzw. Teilnahme geändert haben.
    public func loadIfNeeded() async {
        if case .loaded = state, loadedKey == reloadKey { return }
        if loadTask != nil, loadedKey == reloadKey { return }
        await load()
    }

    /// Lädt neu, wenn der letzte Versuch länger als `maximumAge` zurückliegt – z. B. nachdem neue Schritte da sind.
    /// Gilt auch nach Fehlern, damit offline nicht bei jeder Schrittänderung erneut angefragt wird.
    public func refreshIfStale(maximumAge: Duration = .seconds(60)) async {
        if let lastAttemptAt, ContinuousClock.now - lastAttemptAt < maximumAge, loadedKey == reloadKey { return }
        await load()
    }

    /// Lädt die Platzierungen. Läuft bereits ein Ladevorgang, wird danach genau einmal neu geladen.
    public func load() async {
        if let loadTask {
            needsReload = true
            await loadTask.value
            return
        }
        let task = Task { await self.runLoads() }
        loadTask = task
        await task.value
    }

    private func runLoads() async {
        repeat {
            needsReload = false
            await performLoad()
        } while needsReload
        loadTask = nil
    }

    private func performLoad() async {
        let key = reloadKey
        lastAttemptAt = .now
        loadedKey = key
        if !showsResults(for: key) {
            state = .loading
        }

        do {
            try await store.loadHierarchyIfNeeded()
        } catch {
            state = .failed(message: Self.message(for: error))
            return
        }
        guard let hierarchy = store.hierarchy, key == reloadKey else {
            needsReload = true
            return
        }
        let scopes = hierarchy.leaderboardScopes

        // Ohne Zustimmung erscheint der Nutzer in keinem Ranking – dafür keine Abfragen.
        guard key.isParticipating else {
            state = .loaded(RegionalStandings(scopes: scopes, neighborhoods: [:], isParticipating: false))
            return
        }

        // Eigene Schritte zuerst hochladen, damit die Platzierung stimmt.
        await syncing?.flush()
        guard key == reloadKey else {
            needsReload = true
            return
        }

        let date = calendar.day(containing: now())
        let repository = leaderboards
        let radii = key.neighborhoodRadii
        do {
            let neighborhoods = try await withThrowingTaskGroup(of: (RegionID, [LeaderboardEntry]).self) { group in
                for scope in scopes {
                    let query = LeaderboardQuery(regionID: scope.id, period: .daily, date: date)
                    let radius = radii[scope.level] ?? 0
                    group.addTask { (scope.id, try await repository.neighborhood(for: query, radius: radius)) }
                }
                var result: [RegionID: [LeaderboardEntry]] = [:]
                for try await (id, entries) in group {
                    result[id] = entries
                }
                return result
            }
            guard key == reloadKey else {
                needsReload = true
                return
            }
            state = .loaded(RegionalStandings(scopes: scopes, neighborhoods: neighborhoods, isParticipating: true))
        } catch {
            // Bei einem Fehler bleibt eine bereits angezeigte Platzierung derselben Gemeinde sichtbar.
            if showsResults(for: key) { return }
            state = .failed(message: Self.message(for: error))
        }
    }

    /// Ob bereits Platzierungen für diese Gemeinde und Teilnahme angezeigt werden.
    private func showsResults(for key: ReloadKey) -> Bool {
        guard let standings else { return false }
        return standings.isParticipating == key.isParticipating
            && standings.scopes.first?.region.id == key.municipalityID
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

    static func message(for error: Error) -> String {
        if error as? LeaderboardError == .network || error as? RegionError == .network {
            return "Platzierungen gerade nicht verfügbar. Prüfe deine Verbindung."
        }
        return "Platzierungen konnten nicht geladen werden."
    }
}

/// Geladene Platzierungen.
public struct RegionalStandings: Equatable, Sendable {
    public struct Scope: Equatable, Sendable, Identifiable {
        public let region: Region
        /// `nil`, wenn der Nutzer in diesem Ranking (noch) nicht erscheint.
        public let rank: Int?

        public var id: RegionID { region.id }

        /// z. B. `Stadt`, `Gemeinde`, `Landkreis`, `Bundesland`, `Land`.
        public var levelTitle: String {
            switch region.level {
            case .municipality:
                switch region.kind {
                case .stadt, .grosseKreisstadt, .kreisfreieStadt: "Stadt"
                case .markt: "Markt"
                default: "Gemeinde"
                }
            case .district:
                switch region.kind {
                case .kreis: "Kreis"
                case .regionalverband: "Regionalverband"
                case .kreisfreieStadt, .stadtkreis: "Stadt"
                default: "Landkreis"
                }
            case .state: "Bundesland"
            case .country: "Land"
            }
        }

        /// z. B. `#12`, ohne Platzierung `–`.
        public var rankText: String {
            rank.map { "#\($0.paceFormatted)" } ?? "–"
        }
    }

    /// Umfeld in einem Ranking: Plätze um den eigenen.
    public struct Neighborhood: Equatable, Sendable {
        public let region: Region
        public let entries: [LeaderboardEntry]
        public let currentUser: LeaderboardEntry
        /// Der Platz direkt über dem eigenen (auch wenn er nicht in `entries` steht).
        public let nextAbove: LeaderboardEntry?
        /// Niemand außer dem Nutzer ist heute in diesem Ranking.
        public let isAlone: Bool

        /// Schritte, die zum nächsten Platz fehlen (bei Gleichstand gewinnt, wer den Wert zuerst hatte).
        public var stepsToNextPlace: Int? {
            RankingHint.stepsToNextPlace(currentUser: currentUser, above: nextAbove)
        }

        /// z. B. `Noch 280 Schritte bis Platz #11`. Auf Platz 1 gibt es keinen Aufstiegshinweis.
        public var footerText: String {
            RankingHint.text(currentUser: currentUser, above: nextAbove, isAlone: isAlone, locative: region.locative) ?? ""
        }
    }

    /// Geladene Einträge einer Ebene.
    private struct Loaded: Equatable, Sendable {
        let region: Region
        let entries: [LeaderboardEntry]
    }

    public let scopes: [Scope]
    public let isParticipating: Bool
    private let loaded: [RegionLevel: Loaded]

    public init(scopes regions: [Region], neighborhoods: [RegionID: [LeaderboardEntry]], isParticipating: Bool) {
        self.isParticipating = isParticipating
        scopes = regions.map { region in
            let entries = neighborhoods[region.id] ?? []
            return Scope(region: region, rank: entries.first(where: \.isCurrentUser)?.rank)
        }
        var loaded: [RegionLevel: Loaded] = [:]
        for region in regions {
            guard let entries = neighborhoods[region.id] else { continue }
            loaded[region.level] = Loaded(region: region, entries: entries.sorted { $0.rank < $1.rank })
        }
        self.loaded = loaded
    }

    /// Umfeld in der Gemeinde mit drei Zeilen; `nil`, wenn der Nutzer dort (noch) nicht im Ranking ist.
    public var neighborhood: Neighborhood? {
        neighborhood(for: .municipality, rows: 3)
    }

    /// Umfeld einer Ebene mit bis zu `rows` Zeilen; `nil`, wenn der Nutzer dort (noch) nicht im Ranking ist.
    public func neighborhood(for level: RegionLevel, rows: Int) -> Neighborhood? {
        guard let loaded = loaded[level],
              let index = loaded.entries.firstIndex(where: \.isCurrentUser)
        else { return nil }
        let entries = loaded.entries
        let window = Self.window(around: index, count: entries.count, size: rows)
        let currentUser = entries[index]
        return Neighborhood(
            region: loaded.region,
            entries: Array(entries[window]),
            currentUser: currentUser,
            nextAbove: entries.first { $0.rank == currentUser.rank - 1 },
            isAlone: entries.count == 1
        )
    }

    /// Zeilen um den eigenen Platz: so mittig wie möglich, am Rand mehr Zeilen auf der anderen Seite.
    static func window(around index: Int, count: Int, size requested: Int = 3) -> ClosedRange<Int> {
        let size = min(max(requested, 1), count)
        let start = min(max(index - (size - 1) / 2, 0), count - size)
        return start...(start + size - 1)
    }
}
