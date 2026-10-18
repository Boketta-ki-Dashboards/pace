import Foundation
import Observation
import PaceCore

/// Detailansicht einer Gruppe: Gruppen-Streak, Ranking (heute/Woche), Verlauf der Gruppentage, Einladungen und – für
/// die Person, die die Gruppe verwaltet – Einstellungen.
@MainActor
@Observable
public final class GroupDetailViewModel: Identifiable {
    public enum State: Equatable {
        case loading
        case loaded
        case failed(String)
        /// Die Gruppe existiert nicht mehr oder man ist kein Mitglied mehr (z. B. nach Austritt oder Entfernen).
        case gone
    }

    public private(set) var group: GroupSummary
    public private(set) var state: State = .loading
    public private(set) var period: LeaderboardPeriod = .daily

    public private(set) var ranking: GroupRanking?
    /// Zeitraum, zu dem `ranking` gehört.
    public private(set) var rankingPeriod: LeaderboardPeriod?
    /// Die neueste Ranking-Anfrage ist fehlgeschlagen.
    public private(set) var rankingFailed = false
    public private(set) var days: [GroupDay] = []
    public private(set) var outgoingInvitations: [OutgoingGroupInvitation] = []
    public private(set) var notice: SocialViewModel.Notice?
    public private(set) var isWorking = false

    public nonisolated var id: UUID { groupID }

    @ObservationIgnored private nonisolated let groupID: UUID
    @ObservationIgnored private let repository: any SocialRepository
    @ObservationIgnored private weak var social: SocialViewModel?
    /// Zählt Ranking-Anfragen. Eine Antwort gilt nur für den noch gewählten Zeitraum und nur, wenn keine später
    /// gestartete schon angewendet wurde – sonst überschriebe eine langsame ältere Antwort (z. B. „Heute“) die gerade
    /// gewählte Ansicht („Diese Woche“). Scheitert die neueste Anfrage, bleibt eine gültige ältere so erhalten.
    @ObservationIgnored private var rankingGeneration = 0
    @ObservationIgnored private var appliedRankingGeneration = 0
    @ObservationIgnored private var loadErrorNotice: SocialViewModel.Notice?

    public init(group: GroupSummary, repository: any SocialRepository, social: SocialViewModel?) {
        self.group = group
        groupID = group.id
        self.repository = repository
        self.social = social
    }

    /// Das Ranking des gewählten Zeitraums; `nil`, solange es lädt oder nur das des anderen Zeitraums da ist.
    public var currentRanking: GroupRanking? {
        rankingPeriod == period ? ranking : nil
    }

    /// Freunde, die noch nicht in der Gruppe sind und eingeladen werden können.
    public var invitableFriends: [Friend] {
        let members = Set(ranking?.entries.map(\.profile.publicID) ?? [])
        let invited = Set(outgoingInvitations.map(\.profile.publicID))
        return (social?.friends ?? []).filter { !members.contains($0.profile.publicID) && !invited.contains($0.profile.publicID) }
    }

    /// z. B. `1 von 2 nötigen Mitgliedern haben das Ziel erreicht`.
    public var todayText: String {
        let needed = group.todayRequiredCount
        return "\(group.todayReachedCount) von \(needed) \(needed == 1 ? "nötigem Mitglied" : "nötigen Mitgliedern") "
            + "\(group.todayReachedCount == 1 ? "hat" : "haben") das Ziel erreicht"
    }

    public func load() async {
        // „Erneut versuchen“ zeigt wieder den Ladezustand statt unverändert den Fehler.
        if case .failed = state {
            state = .loading
        }
        rankingGeneration += 1
        rankingFailed = false
        let generation = rankingGeneration
        let requestedPeriod = period
        do {
            async let summary = repository.group(groupID)
            async let ranking = repository.groupRanking(groupID, period: requestedPeriod)
            async let days = repository.groupDays(groupID, count: 14)
            async let invitations = repository.outgoingInvitations(for: groupID)
            let loaded = try await (summary, ranking, days, invitations)
            group = loaded.0
            applyRanking(loaded.1, period: requestedPeriod, generation: generation)
            self.days = loaded.2
            outgoingInvitations = loaded.3
            state = .loaded
            if let loadErrorNotice, notice == loadErrorNotice {
                notice = nil
            }
            loadErrorNotice = nil
        } catch SocialError.notFound {
            state = .gone
        } catch is CancellationError {
            return
        } catch {
            if generation == rankingGeneration {
                rankingFailed = true
            }
            if state == .loaded {
                let notice = SocialViewModel.Notice(text: SocialViewModel.message(for: error), isError: true)
                self.notice = notice
                loadErrorNotice = notice
            } else {
                state = .failed(SocialViewModel.message(for: error))
            }
        }
    }

    /// Wechselt zwischen Tages- und Wochenranking.
    public func select(_ period: LeaderboardPeriod) async {
        guard period != self.period else { return }
        self.period = period
        await loadRanking()
    }

    /// Lädt das Ranking des gewählten Zeitraums erneut (z. B. nach einem Fehler).
    public func reloadRanking() async {
        await loadRanking()
    }

    private func loadRanking() async {
        rankingGeneration += 1
        rankingFailed = false
        let generation = rankingGeneration
        let requestedPeriod = period
        do {
            let result = try await repository.groupRanking(groupID, period: requestedPeriod)
            applyRanking(result, period: requestedPeriod, generation: generation)
        } catch is CancellationError {
            return
        } catch {
            guard generation == rankingGeneration else { return }
            rankingFailed = true
            let notice = SocialViewModel.Notice(text: SocialViewModel.message(for: error), isError: true)
            self.notice = notice
            loadErrorNotice = notice
        }
    }

    private func applyRanking(_ result: GroupRanking, period requestedPeriod: LeaderboardPeriod, generation: Int) {
        guard requestedPeriod == period, generation > appliedRankingGeneration else { return }
        ranking = result
        rankingPeriod = requestedPeriod
        appliedRankingGeneration = generation
        rankingFailed = false
    }

    // MARK: Einladen

    public func invite(_ friend: Friend) async {
        await perform {
            switch try await self.repository.invite(friend.profile.publicID, to: self.groupID) {
            case .invited: "\(friend.profile.displayName) wurde eingeladen."
            case .alreadyMember: "\(friend.profile.displayName) ist bereits Mitglied."
            case .alreadyInvited: "\(friend.profile.displayName) ist bereits eingeladen."
            }
        }
    }

    public func cancel(_ invitation: OutgoingGroupInvitation) async {
        await perform {
            try await self.repository.cancelInvitation(invitation.id)
            return "Einladung zurückgezogen."
        }
    }

    // MARK: Verwalten (nur Eigentümer – der Server prüft das zusätzlich)

    public func regenerateInviteCode() async {
        await perform {
            self.group = try await self.repository.regenerateInviteCode(self.groupID)
            return "Neuer Einladungscode erstellt. Der alte Code gilt nicht mehr."
        }
    }

    public func update(name: String, description: String, kind: GroupKind) async -> Bool {
        let draft = GroupDraft(name: name, description: description, kind: kind)
        guard let validName = draft.validName else {
            show(SocialViewModel.Notice(text: SocialError.invalidName.message, isError: true))
            return false
        }
        guard let validDescription = draft.validDescription else {
            show(SocialViewModel.Notice(text: SocialError.invalidDescription.message, isError: true))
            return false
        }
        return await perform {
            self.group = try await self.repository.updateGroup(self.groupID, name: validName, description: validDescription, kind: kind)
            return "Gruppe gespeichert."
        }
    }

    /// Das neue Ziel gilt ab dem nächsten Gruppentag – heute und vergangene Tage ändern sich nicht.
    public func setGoal(_ goal: Int) async -> Bool {
        await perform {
            self.group = try await self.repository.setGroupGoal(self.groupID, dailyGoal: goal)
            return "Das neue Gruppenziel gilt ab morgen."
        }
    }

    public func remove(_ member: GroupRankingEntry) async {
        await perform {
            try await self.repository.removeMember(member.profile.publicID, from: self.groupID)
            return "\(member.profile.displayName) wurde aus der Gruppe entfernt."
        }
    }

    /// Verlässt die Gruppe. Verwaltet man sie, übernimmt das am längsten beigetretene Mitglied; als letztes Mitglied
    /// wird die Gruppe gelöscht.
    public func leave() async -> Bool {
        let left = await perform(reload: false) {
            try await self.repository.leaveGroup(self.groupID)
            return "Du hast „\(self.group.name)“ verlassen."
        }
        if left { state = .gone }
        await social?.load()
        return left
    }

    public func delete() async -> Bool {
        let deleted = await perform(reload: false) {
            try await self.repository.deleteGroup(self.groupID)
            return "Gruppe „\(self.group.name)“ gelöscht."
        }
        if deleted { state = .gone }
        await social?.load()
        return deleted
    }

    public func dismissNotice() {
        show(nil)
    }

    /// Hinweis einer Aktion; ein späteres erfolgreiches Laden entfernt ihn nicht (siehe `SocialViewModel.show`).
    private func show(_ notice: SocialViewModel.Notice?) {
        self.notice = notice
        loadErrorNotice = nil
    }

    @discardableResult
    private func perform(reload: Bool = true, _ action: @MainActor () async throws -> String) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let text = try await action()
            show(SocialViewModel.Notice(text: text, isError: false))
            if reload { await load() }
            return true
        } catch {
            show(SocialViewModel.Notice(text: SocialViewModel.message(for: error), isError: true))
            if reload { await load() }
            return false
        }
    }
}

/// Profil eines Freundes: nur Namen und Wettbewerbsschritte (heute, diese Woche).
@MainActor
@Observable
public final class FriendProfileViewModel {
    public enum State: Equatable {
        case loading
        case loaded(FriendProfileDetails)
        case failed(String)
        case removed
    }

    public let profile: SocialProfile
    public private(set) var state: State = .loading
    public private(set) var isRemoving = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let repository: any SocialRepository
    @ObservationIgnored private weak var social: SocialViewModel?
    @ObservationIgnored private let calendar: ActivityCalendar
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(
        profile: SocialProfile,
        repository: any SocialRepository,
        social: SocialViewModel?,
        calendar: ActivityCalendar = ActivityCalendar(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.profile = profile
        self.repository = repository
        self.social = social
        self.calendar = calendar
        self.now = now
    }

    public func load() async {
        if case .failed = state {
            state = .loading
        }
        do {
            state = .loaded(try await repository.friendProfile(profile.publicID, date: calendar.day(containing: now())))
        } catch SocialError.notFound {
            state = .removed
        } catch is CancellationError {
            return
        } catch {
            state = .failed(SocialViewModel.message(for: error))
        }
    }

    public func remove() async {
        guard !isRemoving else { return }
        isRemoving = true
        errorMessage = nil
        defer { isRemoving = false }
        do {
            try await repository.removeFriend(profile.publicID)
            state = .removed
            await social?.load()
        } catch {
            errorMessage = SocialViewModel.message(for: error)
        }
    }
}
