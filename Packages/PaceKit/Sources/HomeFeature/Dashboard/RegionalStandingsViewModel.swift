import Foundation
import Observation
import PaceCore

/// Eigene Platzierung in jeder Ranking-Ebene (Gemeinde, Kreis, Bundesland, Land) und das Umfeld in der Gemeinde.
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
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastLoadedAt: ContinuousClock.Instant?
    @ObservationIgnored private var loadedKey: ReloadKey?

    public struct ReloadKey: Hashable, Sendable {
        let municipalityID: RegionID?
        let isParticipating: Bool
    }

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
        ReloadKey(municipalityID: store.profile.municipalityID, isParticipating: isParticipating)
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
        await load()
    }

    /// Lädt neu, wenn die letzten Daten älter als `maximumAge` sind – z. B. nachdem neue Schritte da sind.
    public func refreshIfStale(maximumAge: Duration = .seconds(60)) async {
        if let lastLoadedAt, ContinuousClock.now - lastLoadedAt < maximumAge, loadedKey == reloadKey { return }
        await load()
    }

    public func load() async {
        generation += 1
        let current = generation
        let key = reloadKey
        if case .loaded = state, loadedKey == key {} else {
            state = .loading
        }

        do {
            try await store.loadHierarchyIfNeeded()
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            state = .failed(message: Self.message(for: error))
            return
        }
        guard current == generation, !Task.isCancelled, let hierarchy = store.hierarchy else { return }

        // Eigene Schritte zuerst hochladen, damit die Platzierung stimmt.
        await syncing?.flush()

        let date = calendar.day(containing: now())
        let scopes = hierarchy.leaderboardScopes
        let repository = leaderboards
        do {
            let neighborhoods = try await withThrowingTaskGroup(of: (RegionID, [LeaderboardEntry]).self) { group in
                for scope in scopes {
                    let query = LeaderboardQuery(regionID: scope.id, period: .daily, date: date)
                    // In der Gemeinde zwei Nachbarn je Richtung, damit auch Platz 1 und der Letzte drei Zeilen haben.
                    let radius = scope.level == .municipality ? 2 : 0
                    group.addTask { (scope.id, try await repository.neighborhood(for: query, radius: radius)) }
                }
                var result: [RegionID: [LeaderboardEntry]] = [:]
                for try await (id, entries) in group {
                    result[id] = entries
                }
                return result
            }
            guard current == generation, !Task.isCancelled else { return }
            state = .loaded(RegionalStandings(scopes: scopes, neighborhoods: neighborhoods, isParticipating: key.isParticipating))
            loadedKey = key
            lastLoadedAt = .now
        } catch {
            guard current == generation, !Task.isCancelled, !(error is CancellationError) else { return }
            if case .loaded = state, loadedKey == key { return }
            state = .failed(message: Self.message(for: error))
        }
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
            rank.map { "#\($0.formatted(.number.locale(Locale(identifier: "de_DE"))))" } ?? "–"
        }
    }

    /// Umfeld in der Gemeinde: Platz über mir, ich, Platz unter mir.
    public struct Neighborhood: Equatable, Sendable {
        public let region: Region
        public let entries: [LeaderboardEntry]
        public let currentUser: LeaderboardEntry
        /// Niemand außer dem Nutzer ist heute in diesem Ranking.
        public let isAlone: Bool

        /// Schritte, die zum nächsten Platz fehlen (bei Gleichstand gewinnt, wer den Wert zuerst hatte).
        public var stepsToNextPlace: Int? {
            guard let above = entries.first(where: { $0.rank == currentUser.rank - 1 }) else { return nil }
            return above.competitionSteps - currentUser.competitionSteps + 1
        }

        /// z. B. `Noch 280 Schritte bis Platz #11`.
        public var footerText: String {
            if isAlone {
                return "Du bist der Erste \(region.locative)."
            }
            if currentUser.rank == 1 {
                return "Du führst \(region.locative)."
            }
            guard let steps = stepsToNextPlace else { return "" }
            let formatted = steps.formatted(.number.locale(Locale(identifier: "de_DE")))
            return "Noch \(formatted) \(steps == 1 ? "Schritt" : "Schritte") bis Platz #\(currentUser.rank - 1)"
        }
    }

    public let scopes: [Scope]
    /// `nil`, wenn der Nutzer in der Gemeinde (noch) nicht im Ranking ist.
    public let neighborhood: Neighborhood?
    public let isParticipating: Bool

    public init(scopes regions: [Region], neighborhoods: [RegionID: [LeaderboardEntry]], isParticipating: Bool) {
        self.isParticipating = isParticipating
        scopes = regions.map { region in
            let entries = neighborhoods[region.id] ?? []
            return Scope(region: region, rank: entries.first(where: \.isCurrentUser)?.rank)
        }
        if let municipality = regions.first(where: { $0.level == .municipality }),
           let entries = neighborhoods[municipality.id]?.sorted(by: { $0.rank < $1.rank }),
           let index = entries.firstIndex(where: \.isCurrentUser) {
            let window = Self.window(around: index, count: entries.count)
            neighborhood = Neighborhood(
                region: municipality,
                entries: Array(entries[window]),
                currentUser: entries[index],
                isAlone: entries.count == 1
            )
        } else {
            neighborhood = nil
        }
    }

    /// Drei Zeilen um den eigenen Platz: normalerweise einer darüber und einer darunter, am Rand zwei auf einer Seite.
    static func window(around index: Int, count: Int) -> ClosedRange<Int> {
        let size = min(3, count)
        let start = min(max(index - 1, 0), count - size)
        return start...(start + size - 1)
    }
}
