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

    /// Eine eigene Gruppe mit ihrem Tagesranking; `ranking` ist `nil`, wenn es nicht geladen werden konnte.
    public struct GroupStanding: Equatable, Sendable, Identifiable {
        public let group: GroupSummary
        public let ranking: GroupRanking?

        public var id: UUID { group.id }

        /// Höchstens drei Plätze von oben plus – falls weiter unten – die eigene Zeile.
        public var visibleEntries: [GroupRankingEntry] {
            guard let ranking else { return [] }
            let top = Array(ranking.entries.prefix(3))
            guard let me = ranking.entries.first(where: \.isCurrentUser), !top.contains(me) else { return top }
            return top + [me]
        }

        /// Ob zwischen den oberen Plätzen und der eigenen Zeile Plätze ausgelassen sind.
        public var hasGap: Bool {
            guard let ranking, let me = ranking.entries.first(where: \.isCurrentUser) else { return false }
            return me.rank > 4
        }
    }

    /// Gruppen-Rankings (alle eigenen Gruppen, Tageswerte nach Gruppentag).
    public enum GroupsState: Equatable {
        case idle
        case loading
        case loaded([GroupStanding])
        case failed(message: String)
    }

    /// Höchstens so viele Gruppen werden auf einmal geladen.
    public static let maximumGroups = 12

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
    /// Die Gruppen-Rankings sind ausgewählt.
    public private(set) var isShowingGroups = false
    public private(set) var groups: GroupsState = .idle

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
    @ObservationIgnored private var groupsLoadedAt: ContinuousClock.Instant?
    @ObservationIgnored private var isLoadingGroups = false

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
        !isShowingFriends && !isShowingGroups && state == .hidden
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
    /// Ein eigener Spitzname für eine Person wurde geändert (Social-Tab): Freunde- und Gruppenrankings zeigen ihn
    /// sofort, ohne neu zu laden.
    public func nicknameDidChange(_ profile: SocialProfile) {
        if case .loaded(let entries) = friends {
            friends = .loaded(entries.map { entry in
                entry.publicUserID == profile.publicID ? entry.withNickname(profile.nickname) : entry
            })
        }
        if case .loaded(let standings) = groups {
            groups = .loaded(standings.map { standing in
                guard let ranking = standing.ranking else { return standing }
                let entries = ranking.entries.map { entry in
                    guard entry.profile.publicID == profile.publicID else { return entry }
                    return GroupRankingEntry(
                        rank: entry.rank,
                        profile: entry.profile.withNickname(profile.nickname),
                        competitionSteps: entry.competitionSteps,
                        isCurrentUser: entry.isCurrentUser,
                        role: entry.role,
                        reachedGoalToday: entry.reachedGoalToday
                    )
                }
                return GroupStanding(
                    group: standing.group,
                    ranking: GroupRanking(
                        totalParticipants: ranking.totalParticipants,
                        groupToday: ranking.groupToday,
                        dailyGoal: ranking.dailyGoal,
                        entries: entries
                    )
                )
            })
        }
    }

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
        if isShowingGroups {
            await loadGroupsIfNeeded()
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
        let wasShowingOther = isShowingFriends || isShowingGroups
        isShowingFriends = false
        isShowingGroups = false
        guard scope.id != selectedScope?.id else {
            if wasShowingOther { await loadIfNeeded() }
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
        isShowingGroups = false
        isShowingFriends = true
        await loadFriendsIfNeeded()
    }

    /// Zeigt die Rankings der eigenen Gruppen.
    public func selectGroups() async {
        guard offersFriends else { return }
        isShowingFriends = false
        isShowingGroups = true
        await loadGroupsIfNeeded()
    }

    /// Pull-to-Refresh: liest die eigenen Schritte neu und lädt das Ranking, ohne die Anzeige vorher zu verwerfen.
    public func refresh() async {
        await refreshActivity?()
        if isShowingFriends {
            await syncing?.flush()
            await loadFriends()
        } else if isShowingGroups {
            await syncing?.flush()
            await loadGroups()
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
        if isShowingGroups {
            groups = .loading
            await loadGroups()
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

    // MARK: Gruppen

    private func loadGroupsIfNeeded() async {
        if case .loaded = groups, let groupsLoadedAt, ContinuousClock.now - groupsLoadedAt < maximumAge { return }
        await loadGroups()
    }

    private func loadGroups() async {
        guard let social, !isLoadingGroups else { return }
        isLoadingGroups = true
        defer { isLoadingGroups = false }
        if case .loaded = groups {} else { groups = .loading }
        do {
            let mine = Array(try await social.myGroups().prefix(Self.maximumGroups))
            let period = period
            // Rankings parallel laden; scheitert eine Gruppe, bleibt nur ihre Karte ohne Plätze.
            let rankings = await withTaskGroup(of: (UUID, GroupRanking?).self) { group in
                for summary in mine {
                    group.addTask {
                        (summary.id, try? await social.groupRanking(summary.id, period: period))
                    }
                }
                var result: [UUID: GroupRanking] = [:]
                for await (id, ranking) in group {
                    if let ranking { result[id] = ranking }
                }
                return result
            }
            groups = .loaded(mine.map { GroupStanding(group: $0, ranking: rankings[$0.id]) })
            groupsLoadedAt = .now
        } catch is CancellationError {
            if case .loading = groups { groups = .idle }
        } catch {
            if case .loaded = groups { return }
            groups = .failed(message: Self.message(for: error))
        }
    }

    // MARK: Freunde (laden)

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
        if error as? SocialError == .unavailable {
            // Freunde- und Gruppen-Rankings ohne Social-Migration auf dem Server: kein „erneut versuchen“.
            return SocialError.unavailable.message
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
