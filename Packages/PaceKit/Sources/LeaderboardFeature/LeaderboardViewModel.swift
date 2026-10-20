import Foundation
import Observation
import PaceCore

/// Tagesrankings für die vier regionalen Ebenen des Nutzers und – falls verfügbar – für seine Freunde.
///
/// Sortierung, Plätze und Pagination kommen vom Server. Geladen werden die Top-Plätze und – falls der Nutzer nicht
/// darunter ist – seine eigene Position mit den direkten Nachbarn.
///
/// Ist die Ranking-Sichtbarkeit ausgeschaltet, lädt das ViewModel keine regionalen Rankings (Zustand `.hidden`):
/// Die Ansicht zeigt dann nur eine unscharfe Struktur mit neutralen Platzhaltern. Das Freunde-Ranking ist davon
/// unabhängig – Freunde teilen ihre Wettbewerbsschritte mit der Freundschaft, nicht über die regionale Sichtbarkeit.
@MainActor
@Observable
public final class LeaderboardViewModel {
    public enum State: Equatable {
        case loading
        case loaded(LeaderboardSnapshot)
        case failed(message: String)
        /// Ranking-Sichtbarkeit ausgeschaltet: Es wird nichts geladen und nichts angezeigt.
        case hidden
    }

    /// Freunde-Ranking (ich und meine Freunde, Tageswerte).
    public enum FriendsState: Equatable {
        case idle
        case loading
        case loaded([LeaderboardEntry])
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
    public private(set) var isLoadingMore = false
    public private(set) var loadMoreError: String?
    /// Das Freunde-Ranking ist ausgewählt (statt einer regionalen Ebene).
    public private(set) var isShowingFriends = false
    public private(set) var friends: FriendsState = .idle

    /// Vom Nutzer gewählte Ebene; `nil` bedeutet die Gemeinde.
    private var selectedScopeID: RegionID?

    @ObservationIgnored private let store: ProfileStore
    @ObservationIgnored private let loader: LeaderboardLoader
    @ObservationIgnored private let syncing: (any ActivitySyncing)?
    @ObservationIgnored private let refreshActivity: (@MainActor () async -> Void)?
    @ObservationIgnored private let calendar: ActivityCalendar
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let maximumAge: Duration
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var inFlightKey: LoadKey?
    @ObservationIgnored private var loadedKey: LoadKey?
    @ObservationIgnored private var lastLoadedAt: ContinuousClock.Instant?
    @ObservationIgnored private let social: (any SocialRepository)?
    @ObservationIgnored private var friendsLoadedAt: ContinuousClock.Instant?
    @ObservationIgnored private var isLoadingFriends = false

    /// - Parameters:
    ///   - syncing: Sendet zurückgehaltene Schritte vor dem Laden, damit der eigene Platz aktuell ist.
    ///   - refreshActivity: Liest bei Pull-to-Refresh zuerst die eigenen Schritte neu (in der App: aus Apple Health).
    ///   - maximumAge: Nach dieser Zeit lädt `loadIfNeeded()` beim nächsten Erscheinen neu.
    ///   - social: Quelle des Freunde-Rankings; ohne Angabe gibt es nur die regionalen Ebenen.
    public init(
        store: ProfileStore,
        leaderboards: any LeaderboardRepository,
        syncing: (any ActivitySyncing)?,
        refreshActivity: (@MainActor () async -> Void)? = nil,
        calendar: ActivityCalendar = ActivityCalendar(),
        now: @escaping @Sendable () -> Date = { Date() },
        topLimit: Int = 50,
        maximumAge: Duration = .seconds(60),
        social: (any SocialRepository)? = nil
    ) {
        self.store = store
        self.social = social
        self.syncing = syncing
        self.refreshActivity = refreshActivity
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

    /// Ob es ein Freunde-Ranking gibt.
    public var offersFriends: Bool {
        social != nil
    }

    /// Regionale Ebene gewählt, Sichtbarkeit aber ausgeschaltet.
    public var isRankingHidden: Bool {
        !isShowingFriends && state == .hidden
    }

    /// Text für ein leeres Ranking bzw. wenn der Nutzer allein darin ist. `nil`, wenn es nichts zu erklären gibt.
    public var emptyStateText: String? {
        guard let snapshot, let region = scopes.first(where: { $0.id == snapshot.query.regionID }) else { return nil }
        let place = region.locative
        if snapshot.isCurrentUserAlone, let me = snapshot.currentUserEntry {
            return RankingHint.text(currentUser: me, above: nil, isAlone: true, locative: place)
        }
        if snapshot.isEmpty {
            return PaceLocalization.text(
                de: "Heute hat \(place) noch niemand Schritte gesammelt. Deine erscheinen, sobald sie synchronisiert sind.",
                en: "Nobody has collected steps \(place) today yet. Yours appear as soon as they're synced.",
                ru: "Сегодня \(place) ещё никто не набрал шагов. Твои появятся после синхронизации."
            )
        }
        return nil
    }

    /// „unter deinen Freunden“ für Hinweise im Freunde-Ranking.
    public static var friendsLocative: String {
        PaceLocalization.text(de: "unter deinen Freunden", en: "among your friends", ru: "среди друзей")
    }

    /// Aufstiegshinweis im Freunde-Ranking („Noch 280 Schritte bis Platz #2“, „Du führst unter deinen Freunden.“).
    public var friendsProgressText: String? {
        guard case .loaded(let entries) = friends, let me = entries.first(where: \.isCurrentUser) else { return nil }
        let above = entries.first { $0.rank == me.rank - 1 }
        return RankingHint.text(currentUser: me, above: above, isAlone: entries.count == 1, locative: Self.friendsLocative)
    }

    /// Aufstiegshinweis zum eigenen Platz – gleiche Regeln wie „Dein Umfeld“ auf Home. `nil`, wenn der Nutzer nicht
    /// im Ranking ist, allein ist (dann `emptyStateText`) oder der Platz darüber nicht geladen ist.
    public var progressText: String? {
        guard let snapshot, let me = snapshot.currentUserEntry, !snapshot.isCurrentUserAlone,
              let region = scopes.first(where: { $0.id == snapshot.query.regionID })
        else { return nil }
        let above = snapshot.entries.first { $0.rank == me.rank - 1 }
        return RankingHint.text(currentUser: me, above: above, isAlone: false, locative: region.locative)
    }

    /// Lädt beim Erscheinen – nur wenn sich etwas geändert hat, der letzte Versuch fehlschlug oder die Daten älter
    /// als `maximumAge` sind.
    public func loadIfNeeded() async {
        if isShowingFriends {
            await loadFriendsIfNeeded()
            return
        }
        let key = currentLoadKey
        guard inFlightKey != key else { return }
        if case .loaded = state, loadedKey == key, let lastLoadedAt, ContinuousClock.now - lastLoadedAt < maximumAge {
            return
        }
        await load()
    }

    /// Wechselt die Ebene, z. B. von der Gemeinde zum Bundesland (auch zurück aus dem Freunde-Ranking).
    public func select(_ scope: Region) async {
        let wasShowingFriends = isShowingFriends
        isShowingFriends = false
        guard scope.id != selectedScope?.id else {
            if wasShowingFriends { await loadIfNeeded() }
            return
        }
        selectedScopeID = scope.id
        if isParticipating {
            state = .loading
        }
        await load()
    }

    /// Zeigt das Freunde-Ranking.
    public func selectFriends() async {
        guard offersFriends else { return }
        isShowingFriends = true
        await loadFriendsIfNeeded()
    }

    /// Pull-to-Refresh: liest die eigenen Schritte neu und lädt das Ranking, ohne die Anzeige vorher zu verwerfen.
    public func refresh() async {
        await refreshActivity?()
        if isShowingFriends {
            await syncing?.flush()
            await loadFriends()
        } else {
            await load()
        }
    }

    /// „Erneut versuchen“ nach einem Fehler.
    public func retry() async {
        if isShowingFriends {
            friends = .loading
            await loadFriends()
            return
        }
        state = .loading
        await load()
    }

    /// Ob unter den angezeigten Plätzen weitere geladen werden können.
    public var canLoadMore: Bool {
        snapshot?.canLoadMore == true
    }

    /// „Weitere Plätze laden“: die nächsten Plätze nach den lückenlos angezeigten.
    public func loadMore() async {
        guard let current = snapshot, current.canLoadMore, !isLoadingMore else { return }
        let generationAtStart = generation
        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }

        do {
            let extended = try await loader.loadMore(after: current)
            // Wurde inzwischen neu geladen (andere Ebene, Pull-to-Refresh), passt das Ergebnis nicht mehr.
            guard generationAtStart == generation, snapshot == current else { return }
            state = .loaded(extended)
        } catch {
            guard generationAtStart == generation else { return }
            loadMoreError = Self.message(for: error)
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
            participationError = PaceLocalization.text(
                de: "Das hat nicht geklappt. Prüfe deine Verbindung und versuche es erneut.",
                en: "That didn't work. Check your connection and try again.",
                ru: "Не получилось. Проверь подключение и попробуй ещё раз."
            )
            return
        }
        await load()
    }

    // MARK: Freunde

    private func loadFriendsIfNeeded() async {
        if case .loaded = friends, let friendsLoadedAt, ContinuousClock.now - friendsLoadedAt < maximumAge { return }
        await loadFriends()
    }

    private func loadFriends() async {
        guard let social, !isLoadingFriends else { return }
        isLoadingFriends = true
        defer { isLoadingFriends = false }
        if case .loaded = friends {} else { friends = .loading }
        do {
            let entries = try await social.friendRanking(period: period, date: calendar.day(containing: now()))
            friends = .loaded(entries.sorted { $0.rank < $1.rank })
            friendsLoadedAt = .now
        } catch is CancellationError {
            if case .loading = friends { friends = .idle }
        } catch {
            // Pull-to-Refresh ohne Netz: Die alten Werte bleiben sichtbar.
            if case .loaded = friends { return }
            friends = .failed(message: Self.message(for: error))
        }
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
            state = .failed(message: PaceLocalization.text(
                de: "Wähle im Profil eine Gemeinde, um Rankings zu sehen.",
                en: "Choose your municipality in your profile to see rankings.",
                ru: "Выбери населённый пункт в профиле, чтобы видеть рейтинги."
            ))
            return
        }

        // Sichtbarkeit aus: keine fremden Rankingdaten laden – auch nicht „nur für die Unschärfe“.
        guard isParticipating else {
            state = .hidden
            loadedKey = key
            lastLoadedAt = .now
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
        if error as? LeaderboardError == .network || error as? RegionError == .network || error as? SocialError == .network {
            return PaceLocalization.text(
                de: "Keine Verbindung. Prüfe deine Internetverbindung und versuche es erneut.",
                en: "No connection. Check your internet connection and try again.",
                ru: "Нет соединения. Проверь подключение к интернету и попробуй ещё раз."
            )
        }
        if error as? LeaderboardError == .unknownRegion || error as? RegionError == .notFound {
            return PaceLocalization.text(
                de: "Deine Region ist nicht mehr verfügbar. Bitte wähle sie im Profil neu.",
                en: "Your region is no longer available. Please choose it again in your profile.",
                ru: "Твой регион больше недоступен. Выбери его заново в профиле."
            )
        }
        return PaceLocalization.text(
            de: "Das Ranking konnte nicht geladen werden. Bitte versuche es erneut.",
            en: "The ranking couldn't be loaded. Please try again.",
            ru: "Не удалось загрузить рейтинг. Попробуй ещё раз."
        )
    }
}
