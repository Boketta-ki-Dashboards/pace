import Foundation
import Observation
import PaceCore

/// Eine Gruppe: Details mit Gruppen-Streak und Ranking (Referenzbild 4), Mitglieder und Einstellungen.
///
/// Details, Mitglieder- und Einstellungsseite teilen sich dieses ViewModel, damit eine Änderung (z. B. ein neuer Name
/// oder ein entferntes Mitglied) sofort überall erscheint. Alle Werte der Gruppen-Streak – wie viele Mitglieder das Ziel
/// erreicht haben und wie viele es heute braucht – kommen vom Server und werden hier nicht neu berechnet.
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
    /// IDs (Personen, Einladungen), für die gerade eine Aktion läuft.
    public private(set) var busyIDs: Set<UUID> = []

    public nonisolated var id: UUID { groupID }

    @ObservationIgnored private nonisolated let groupID: UUID
    @ObservationIgnored private let repository: any SocialRepository
    @ObservationIgnored private weak var social: SocialViewModel?
    @ObservationIgnored let media: (any MediaRepository)?
    /// Zählt Ranking-Anfragen. Eine Antwort gilt nur für den noch gewählten Zeitraum und nur, wenn keine später
    /// gestartete schon angewendet wurde – sonst überschriebe eine langsame ältere Antwort (z. B. „Heute“) die gerade
    /// gewählte Ansicht („Diese Woche“). Scheitert die neueste Anfrage, bleibt eine gültige ältere so erhalten.
    @ObservationIgnored private var rankingGeneration = 0
    @ObservationIgnored private var appliedRankingGeneration = 0
    @ObservationIgnored private var loadErrorNotice: SocialViewModel.Notice?

    public init(
        group: GroupSummary,
        repository: any SocialRepository,
        social: SocialViewModel?,
        media: (any MediaRepository)? = nil
    ) {
        self.group = group
        groupID = group.id
        self.repository = repository
        self.social = social
        self.media = media
    }

    /// Das Ranking des gewählten Zeitraums; `nil`, solange es lädt oder nur das des anderen Zeitraums da ist.
    public var currentRanking: GroupRanking? {
        rankingPeriod == period ? ranking : nil
    }

    // MARK: Gruppen-Streak (Werte vom Server)

    /// z. B. „4 von 12 Mitgliedern haben heute das Ziel erreicht“.
    public var todayText: String {
        SocialText.reachedToday(group.todayReachedCount, of: group.memberCount)
    }

    /// Erreichte Ziele, die für die Flamme zählen – höchstens so viele, wie heute nötig sind („4 von 4 benötigten“).
    public var countedGoals: Int {
        min(group.todayReachedCount, group.todayRequiredCount)
    }

    /// Ziele, die heute noch fehlen, damit die Flamme gesichert ist.
    public var missingGoals: Int {
        max(group.todayRequiredCount - group.todayReachedCount, 0)
    }

    /// Fortschritt zur gesicherten Flamme (0…1).
    public var requiredProgress: Double {
        guard group.todayRequiredCount > 0 else { return group.todayComplete ? 1 : 0 }
        return min(Double(group.todayReachedCount) / Double(group.todayRequiredCount), 1)
    }

    /// Eine Pille je Mitglied: `true` für jedes Mitglied, das heute das Ziel erreicht hat (Reihenfolge ohne Bedeutung).
    public var memberPills: [Bool] {
        let members = max(group.memberCount, 0)
        let reached = min(max(group.todayReachedCount, 0), members)
        return Array(repeating: true, count: reached) + Array(repeating: false, count: members - reached)
    }

    public var requiredGoalsText: String {
        SocialText.requiredGoals(countedGoals, of: group.todayRequiredCount)
    }

    /// „Flamme gesichert“ bzw. „Noch 2 Ziele“.
    public var flameStatusText: String {
        group.todayComplete ? SocialText.flameSecured : SocialText.goalsMissing(max(missingGoals, 1))
    }

    public var thirdRuleText: String {
        SocialText.thirdRule(required: group.todayRequiredCount, members: group.memberCount)
    }

    // MARK: Mitglieder

    /// Mitglieder laut Ranking: wer die Gruppe verwaltet zuerst, dann nach Namen.
    public var members: [GroupRankingEntry] {
        (ranking?.entries ?? []).sorted { lhs, rhs in
            if lhs.role != rhs.role { return lhs.role == .owner }
            return lhs.profile.shownName.localizedStandardCompare(rhs.profile.shownName) == .orderedAscending
        }
    }

    /// Freunde, die noch nicht in der Gruppe sind und eingeladen werden können.
    public var invitableFriends: [Friend] {
        let members = Set(ranking?.entries.map(\.profile.publicID) ?? [])
        let invited = Set(outgoingInvitations.map(\.profile.publicID))
        return (social?.friends ?? []).filter { !members.contains($0.profile.publicID) && !invited.contains($0.profile.publicID) }
    }

    /// Darf diese Person aus der Gruppe entfernt werden? Nur wer verwaltet, und nie sich selbst.
    public func canRemove(_ member: GroupRankingEntry) -> Bool {
        group.isOwner && !member.isCurrentUser
    }

    /// Ohne Bildspeicher (kein Backend) kann kein Gruppenbild gesetzt werden.
    public var canChangeImage: Bool {
        group.isOwner && media != nil
    }

    // MARK: Laden

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
                let notice = SocialViewModel.Notice(text: SocialText.message(for: error), isError: true)
                self.notice = notice
                loadErrorNotice = notice
            } else {
                state = .failed(SocialText.message(for: error))
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
            let notice = SocialViewModel.Notice(text: SocialText.message(for: error), isError: true)
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

    @discardableResult
    public func invite(_ friend: Friend) async -> Bool {
        await perform(busy: friend.profile.publicID) {
            switch try await self.repository.invite(friend.profile.publicID, to: self.groupID) {
            case .invited: SocialText.invitedNotice(friend.profile.shownName)
            case .alreadyMember: SocialText.alreadyMember(friend.profile.shownName)
            case .alreadyInvited: SocialText.alreadyInvited(friend.profile.shownName)
            }
        }
    }

    @discardableResult
    public func cancel(_ invitation: OutgoingGroupInvitation) async -> Bool {
        await perform(busy: invitation.id) {
            try await self.repository.cancelInvitation(invitation.id)
            return SocialText.invitationWithdrawn
        }
    }

    // MARK: Verwalten (nur wer die Gruppe verwaltet – der Server prüft das zusätzlich)

    @discardableResult
    public func regenerateInviteCode() async -> Bool {
        await perform {
            self.group = try await self.repository.regenerateInviteCode(self.groupID)
            return SocialText.newCodeCreated
        }
    }

    /// Name, Beschreibung und Art (Privatsphäre bleibt).
    @discardableResult
    public func update(name: String, description: String, kind: GroupKind) async -> Bool {
        await updateDetails(name: name, description: description, kind: kind, privacy: group.privacy)
    }

    /// Name, Beschreibung, Art und Privatsphäre. Prüft Länge wie der Server, bevor gesendet wird.
    @discardableResult
    public func updateDetails(name: String, description: String, kind: GroupKind, privacy: GroupPrivacy) async -> Bool {
        let draft = GroupDraft(name: name, description: description, kind: kind, privacy: privacy)
        guard let validName = draft.validName else {
            show(SocialViewModel.Notice(text: SocialError.invalidName.message, isError: true))
            return false
        }
        guard let validDescription = draft.validDescription else {
            show(SocialViewModel.Notice(text: SocialError.invalidDescription.message, isError: true))
            return false
        }
        let saved = await perform {
            self.group = try await self.repository.updateGroupDetails(
                self.groupID, name: validName, description: validDescription, kind: kind, privacy: privacy
            )
            return SocialText.groupSaved
        }
        if saved { await social?.load() }
        return saved
    }

    /// Das neue Ziel gilt ab dem nächsten Gruppentag – heute und vergangene Tage ändern sich nicht. Persönliche
    /// Tagesziele der Mitglieder bleiben unberührt.
    @discardableResult
    public func setGoal(_ goal: Int) async -> Bool {
        guard GroupGoalRules.range.contains(goal) else {
            show(SocialViewModel.Notice(text: SocialError.invalidGoal.message, isError: true))
            return false
        }
        return await perform {
            self.group = try await self.repository.setGroupGoal(self.groupID, dailyGoal: goal)
            return SocialText.goalFromTomorrow
        }
    }

    /// Lädt ein neues, bereits verkleinertes Gruppenbild hoch und setzt es.
    @discardableResult
    public func setImage(_ image: SocialViewModel.GroupImageUpload) async -> Bool {
        guard let media else {
            show(SocialViewModel.Notice(text: SocialText.imageStorageUnavailable, isError: true))
            return false
        }
        guard image.data.count <= MediaRules.maximumBytes(for: .groupImage(groupID: groupID)) else {
            show(SocialViewModel.Notice(text: SocialText.imageTooLarge, isError: true))
            return false
        }
        let saved = await perform {
            let reference = try await media.upload(image.data, contentType: image.contentType, to: .groupImage(groupID: self.groupID))
            self.group = try await self.repository.setGroupImage(self.groupID, path: reference.path)
            return SocialText.groupImageSaved
        }
        if saved { await social?.load() }
        return saved
    }

    @discardableResult
    public func removeImage() async -> Bool {
        let removed = await perform {
            self.group = try await self.repository.setGroupImage(self.groupID, path: nil)
            return SocialText.groupImageRemoved
        }
        if removed { await social?.load() }
        return removed
    }

    @discardableResult
    public func remove(_ member: GroupRankingEntry) async -> Bool {
        let removed = await perform(busy: member.profile.publicID) {
            try await self.repository.removeMember(member.profile.publicID, from: self.groupID)
            return SocialText.memberRemoved(member.profile.shownName)
        }
        if removed { await social?.load() }
        return removed
    }

    /// Verlässt die Gruppe. Verwaltet man sie, übernimmt das am längsten beigetretene Mitglied; als letztes Mitglied
    /// wird die Gruppe gelöscht.
    @discardableResult
    public func leave() async -> Bool {
        let name = group.name
        let left = await perform(reload: false) {
            try await self.repository.leaveGroup(self.groupID)
            return SocialText.leftGroup(name)
        }
        await finishLeaving(left, text: SocialText.leftGroup(name))
        return left
    }

    @discardableResult
    public func delete() async -> Bool {
        let name = group.name
        let deleted = await perform(reload: false) {
            try await self.repository.deleteGroup(self.groupID)
            return SocialText.groupDeleted(name)
        }
        await finishLeaving(deleted, text: SocialText.groupDeleted(name))
        return deleted
    }

    private func finishLeaving(_ succeeded: Bool, text: String) async {
        if succeeded {
            state = .gone
            social?.discardDetail(for: groupID)
            social?.show(SocialViewModel.Notice(text: text, isError: false))
        }
        await social?.load()
    }

    /// Text zum Teilen des Einladungscodes (nur sinnvoll bei Privatsphäre „Mit Einladungscode“).
    public var inviteShareText: String {
        SocialText.joinGroupShareText(name: group.name, code: group.inviteCode)
    }

    public func dismissNotice() {
        show(nil)
    }

    /// Hinweis von außen, z. B. „Gruppe erstellt – Bild konnte nicht gespeichert werden“ direkt nach dem Anlegen.
    func show(_ notice: SocialViewModel.Notice?) {
        self.notice = notice
        loadErrorNotice = nil
    }

    @discardableResult
    private func perform(reload: Bool = true, busy id: UUID? = nil, _ action: @MainActor () async throws -> String) async -> Bool {
        if let id {
            guard !busyIDs.contains(id) else { return false }
        } else {
            guard !isWorking else { return false }
        }
        if let id { busyIDs.insert(id) } else { isWorking = true }
        defer {
            if let id { busyIDs.remove(id) } else { isWorking = false }
        }
        do {
            let text = try await action()
            show(SocialViewModel.Notice(text: text, isError: false))
            if reload { await load() }
            return true
        } catch {
            show(SocialViewModel.Notice(text: SocialText.actionMessage(for: error), isError: true))
            if reload { await load() }
            return false
        }
    }
}
