import Foundation
import Observation
import PaceCore

/// Der Social-Bereich: Freunde, Anfragen, Freundesranking, Gruppen und Einladungen – geteilt zwischen der
/// Social-Hauptseite, ihren Unterseiten und den Home-Modulen.
///
/// Alle Prüfungen (Zugriff, Limits, Gruppen-Streak) erfolgen auf dem Server. Ist das Social-Backend (noch) nicht
/// eingerichtet oder fehlt das Backend ganz, zeigt der Bereich das ehrlich an, statt Funktionen vorzutäuschen.
@MainActor
@Observable
public final class SocialViewModel {
    public enum State: Equatable {
        case idle
        case loading
        case loaded
        /// Kein Social-Backend: Text für den Hinweis.
        case unavailable(String)
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var friends: [Friend] = []
    public private(set) var requests: [FriendRequest] = []
    /// Du und deine Freunde, heute.
    public private(set) var ranking: [LeaderboardEntry] = []
    public private(set) var groups: [GroupSummary] = []
    public private(set) var invitations: [GroupInvitation] = []

    /// Suchfeld der Hauptseite („Freunde und Chats suchen“): filtert Freunde und Chats lokal.
    public var filterText = ""
    /// Rückmeldung der letzten Aktion (Erfolg oder Fehler), z. B. „Anfrage gesendet“.
    public private(set) var notice: Notice?
    /// IDs, für die gerade eine Aktion läuft (Anfrage, Einladung, Person).
    public private(set) var busyIDs: Set<UUID> = []

    public struct Notice: Equatable, Sendable {
        public let text: String
        public let isError: Bool

        public init(text: String, isError: Bool) {
            self.text = text
            self.isError = isError
        }
    }

    /// Ausgewähltes Gruppenbild beim Erstellen: bereits verkleinert und komprimiert.
    public struct GroupImageUpload: Equatable, Sendable {
        public let data: Data
        public let contentType: String

        public init(data: Data, contentType: String = "image/jpeg") {
            self.data = data
            self.contentType = contentType
        }
    }

    /// Höchstgröße eines Gruppenbilds (wie der Bucket `group-images` auf dem Server).
    public nonisolated static var groupImageMaximumBytes: Int {
        MediaRules.maximumBytes(for: .groupImage(groupID: UUID()))
    }

    /// Chats (privat und Gruppen) – geteilt zwischen Social-Hauptseite, Gruppendetails und Profilen.
    public let chats: ChatListViewModel
    /// Navigationspfad des Social-Tabs (eine Quelle für alle Einstiege: Liste, Gruppe, Chat, Widget, Link).
    public let navigator: SocialNavigator
    /// Profil, das von außen geöffnet werden soll (z. B. über einen geteilten Link `pace://u/<name>`).
    public private(set) var requestedProfile: String?
    /// Gruppe, die von außen geöffnet werden soll (z. B. aus einem Gruppen-Widget auf Home).
    public private(set) var requestedGroup: UUID?
    /// Öffnet die Privatsphäre-Einstellungen im Profil-Tab (vom App-Rahmen gesetzt). Ohne Angabe erklären die
    /// Social-Einstellungen nur, wo sich die Auffindbarkeit einstellen lässt.
    public var openPrivacySettings: (@MainActor () -> Void)?
    /// Ein eigener Spitzname wurde geändert – für Ansichten außerhalb des Social-Tabs (z. B. Rankings → Freunde).
    public var onNicknameChange: (@MainActor (SocialProfile) -> Void)?

    @ObservationIgnored private let repository: (any SocialRepository)?
    /// Profil- und Gruppenbilder; `nil` ohne Backend.
    @ObservationIgnored let media: (any MediaRepository)?
    @ObservationIgnored let calendar: ActivityCalendar
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored private let ownUsername: @MainActor () -> String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Während eines Ladevorgangs wurde ein frischer Stand verlangt (z. B. nach einer Aktion).
    @ObservationIgnored private var reloadRequested = false
    @ObservationIgnored private var lastLoadedAt: Date?
    /// Der Hinweis des letzten fehlgeschlagenen Ladens – verschwindet, sobald wieder erfolgreich geladen wurde.
    @ObservationIgnored private var loadErrorNotice: Notice?
    /// Eine Detailansicht je Gruppe: Details, Mitglieder und Einstellungen teilen sich denselben Stand.
    @ObservationIgnored private var groupDetails: [UUID: GroupDetailViewModel] = [:]
    @ObservationIgnored private var groupCalendars: [UUID: GroupCalendarViewModel] = [:]

    /// - Parameters:
    ///   - repository: `nil`, wenn kein Backend konfiguriert ist.
    ///   - ownUsername: Eigener Benutzername zum Teilen.
    ///   - ownProfile: Eigenes Profil für „Profil teilen“ in einem Chat.
    ///   - chats: Chatliste; ohne Angabe ohne Chats.
    ///   - media: Profil- und Gruppenbilder.
    public init(
        repository: (any SocialRepository)?,
        chats: ChatListViewModel? = nil,
        media: (any MediaRepository)? = nil,
        ownUsername: @escaping @MainActor () -> String? = { nil },
        ownProfile: @escaping @MainActor () -> SocialProfile? = { nil },
        calendar: ActivityCalendar = ActivityCalendar(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        let chats = chats ?? ChatListViewModel(repository: nil, media: media)
        self.chats = chats
        let navigator = SocialNavigator { [weak chats] lhs, rhs in
            chats?.isSameChat(lhs, rhs) ?? SocialNavigator.sameChatTarget(lhs, rhs)
        }
        // Geschlossene Chats geben ihren Speicher frei (höchstens wenige bleiben für schnelles Wiederöffnen).
        navigator.onPathChange = { [weak chats, weak navigator] _ in
            guard let navigator else { return }
            chats?.trimCache(keeping: navigator.chatTargets)
        }
        self.navigator = navigator
        self.media = media
        self.ownUsername = ownUsername
        self.calendar = calendar
        self.now = now
        if repository == nil {
            state = .unavailable(SocialError.unavailable.message)
        }
        // „Profil teilen“ im Chat: das eigene Profil, danach die Freunde alphabetisch.
        chats.shareableProfiles = { [weak self] in
            guard let self else { return [] }
            let friends = self.friends.map(\.profile)
                .sorted { $0.shownName.localizedCaseInsensitiveCompare($1.shownName) == .orderedAscending }
            return (ownProfile().map { [$0] } ?? []) + friends
        }
    }

    public var isAvailable: Bool {
        if case .unavailable = state { return false }
        return repository != nil
    }

    public var incomingRequests: [FriendRequest] { requests.filter { $0.direction == .incoming } }
    public var outgoingRequests: [FriendRequest] { requests.filter { $0.direction == .outgoing } }

    /// Text zum Weitergeben des eigenen Profils, mit Link (`pace://u/<name>`).
    public var shareText: String? {
        ownUsername().map { username in
            SocialText.shareProfileText(username: username, isOwn: true) + "\n" + PaceLink.profile(username: username).url.absoluteString
        }
    }

    public var username: String? {
        ownUsername().map { "@\($0)" }
    }

    /// Eigener Benutzername ohne „@“.
    var ownUsernameValue: String? {
        ownUsername()
    }

    /// Die drei Freunde mit den meisten Wettbewerbsschritten heute (ohne dich). Der Platz ist der aus dem
    /// Freundesranking, in dem du mitzählst – wie in der vollständigen Liste.
    public var topFriends: [LeaderboardEntry] {
        Array(ranking.filter { !$0.isCurrentUser }.prefix(3))
    }

    /// `true`, sobald es Freunde gibt (das Ranking enthält immer auch dich).
    public var hasFriends: Bool {
        !friends.isEmpty || ranking.contains { !$0.isCurrentUser }
    }

    /// Heutiger Tag (für Profile und Rankings).
    var today: LocalDate {
        calendar.day(containing: now())
    }

    // MARK: Suche auf der Hauptseite

    /// Suchtext ohne Leerzeichen am Rand und ohne führendes „@“.
    public var normalizedFilter: String {
        Self.normalizedQuery(filterText)
    }

    public var isFiltering: Bool {
        !normalizedFilter.isEmpty
    }

    /// Freunde, deren Spitzname, Anzeige- oder Benutzername den Suchtext enthält.
    public var matchingFriends: [Friend] {
        let query = normalizedFilter
        guard !query.isEmpty else { return [] }
        return friends.filter {
            Self.matches($0.profile.shownName, query) || Self.matches($0.profile.displayName, query)
                || Self.matches($0.profile.username, query)
        }
    }

    /// Chats, deren Name (bzw. Benutzername des Gegenübers) den Suchtext enthält.
    public var matchingConversations: [ConversationSummary] {
        let query = normalizedFilter
        guard !query.isEmpty else { return [] }
        // Gleiche Suche wie in der Chatliste (Name, @Benutzername, Anzeigename des Gegenübers, ohne Akzente).
        return chats.conversations(matching: filterText)
    }

    static func normalizedQuery(_ text: String) -> String {
        var query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while query.hasPrefix("@") {
            query.removeFirst()
        }
        return query
    }

    static func matches(_ text: String, _ query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    // MARK: Von außen öffnen

    /// Öffnet ein Profil über den Benutzernamen (z. B. aus einem geteilten Link). Die Social-Ansicht löst es mit
    /// ``resolveRequestedProfile()`` auf.
    public func showProfile(username: String) {
        requestedProfile = username
    }

    public func clearRequestedProfile() {
        requestedProfile = nil
    }

    /// Öffnet die Details einer Gruppe (z. B. aus einem Home-Widget). Die Social-Ansicht zeigt sie an und setzt die
    /// Anfrage danach mit ``clearRequestedGroup()`` zurück.
    public func showGroup(_ groupID: UUID) {
        requestedGroup = groupID
    }

    public func clearRequestedGroup() {
        requestedGroup = nil
    }

    /// Sucht das angefragte Profil (``requestedProfile``) über den genauen Benutzernamen und setzt die Anfrage zurück.
    /// Gibt es das Profil nicht oder ist es nicht sichtbar, steht ein Hinweis in `notice`.
    public func resolveRequestedProfile() async -> SocialProfile? {
        guard let requested = requestedProfile else { return nil }
        // Erst nach der Server-Antwort zurücksetzen: Die Social-Ansicht startet die Auflösung mit
        // `.task(id: requestedProfile)`; ein früheres Zurücksetzen bräche genau diese Aufgabe samt Anfrage ab.
        defer {
            if requestedProfile == requested { clearRequestedProfile() }
        }
        let username = Self.normalizedQuery(requested)
        guard let repository else {
            show(Notice(text: SocialError.unavailable.message, isError: true))
            return nil
        }
        guard UsernameRules.violation(for: username) == nil else {
            show(Notice(text: SocialText.profileLinkNotFound(username), isError: true))
            return nil
        }
        do {
            if let result = try await repository.findProfile(username: username) {
                return result.profile
            }
            show(Notice(text: SocialText.profileLinkNotFound(username), isError: true))
        } catch {
            show(Notice(text: SocialText.message(for: error), isError: true))
        }
        return nil
    }

    // MARK: Laden

    /// Lädt beim ersten Erscheinen bzw. wenn der Stand älter als eine Minute ist.
    public func loadIfNeeded() async {
        if let lastLoadedAt, now().timeIntervalSince(lastLoadedAt) < 60, state == .loaded { return }
        await load(fresh: false)
    }

    /// Lädt Freunde, Anfragen, Ranking, Gruppen und Einladungen.
    ///
    /// Läuft bereits ein Ladevorgang, wartet der Aufruf auf einen Stand, der erst danach abgefragt wird – sonst
    /// zeigte die Liste nach „Annehmen“ oder „Beitreten“ den Stand von vor der Aktion. Mehrere solche Aufrufe teilen
    /// sich einen zusätzlichen Ladevorgang.
    public func load() async {
        await load(fresh: true)
    }

    /// - Parameter fresh: `false` schließt sich einem laufenden Ladevorgang einfach an.
    private func load(fresh: Bool) async {
        guard repository != nil else { return }
        if let loadTask {
            if fresh { reloadRequested = true }
            await loadTask.value
            return
        }
        let task = Task {
            repeat {
                self.reloadRequested = false
                await self.performLoad()
            } while self.reloadRequested
            // Noch in der Aufgabe freigeben: Ein frischer Aufruf direkt danach startet sonst kein neues Laden,
            // sondern schlösse sich der bereits beendeten Aufgabe an.
            self.loadTask = nil
        }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        guard let repository else { return }
        if state != .loaded {
            state = .loading
        }
        let today = self.today
        do {
            async let friends = repository.friends()
            async let requests = repository.friendRequests()
            async let ranking = repository.friendRanking(period: .daily, date: today)
            async let groups = repository.myGroups()
            async let invitations = repository.groupInvitations()
            let loaded = try await (friends, requests, ranking, groups, invitations)
            self.friends = loaded.0
            self.requests = loaded.1
            self.ranking = loaded.2
            self.groups = loaded.3
            self.invitations = loaded.4
            state = .loaded
            lastLoadedAt = now()
            if let loadErrorNotice, notice == loadErrorNotice {
                notice = nil
            }
            loadErrorNotice = nil
        } catch is CancellationError {
            if state == .loading { state = .idle }
        } catch let error as SocialError where error == .unavailable {
            state = .unavailable(error.message)
        } catch {
            // Bereits geladene Daten bleiben sichtbar; der Fehler erscheint als Hinweis.
            if state == .loaded {
                let notice = Notice(text: SocialText.message(for: error), isError: true)
                self.notice = notice
                loadErrorNotice = notice
            } else {
                state = .failed(SocialText.message(for: error))
            }
        }
    }

    // MARK: Freunde

    /// Sendet eine Freundschaftsanfrage. Gibt die Antwort des Servers zurück oder `nil` bei Fehlern (Text in `notice`).
    @discardableResult
    public func sendRequest(to profile: SocialProfile) async -> FriendRequestOutcome? {
        var outcome: FriendRequestOutcome?
        let succeeded = await perform(on: profile.publicID) { repository in
            let result = try await repository.sendFriendRequest(to: profile.publicID)
            outcome = result
            switch result {
            case .requested: return SocialText.requestSent(to: profile.shownName)
            case .accepted: return SocialText.nowFriends(with: profile.shownName)
            case .alreadyFriends: return SocialText.alreadyFriendsNotice
            case .alreadyRequested: return SocialText.alreadyRequestedNotice
            }
        }
        return succeeded ? outcome : nil
    }

    @discardableResult
    public func respond(to request: FriendRequest, accept: Bool) async -> Bool {
        await respondToRequest(request.id, from: request.profile, accept: accept)
    }

    /// Antwortet auf eine Anfrage, deren ID bekannt ist (z. B. aus einem Suchtreffer oder Profil).
    @discardableResult
    public func respondToRequest(_ requestID: UUID, from profile: SocialProfile, accept: Bool) async -> Bool {
        await perform(on: requestID, also: profile.publicID) { repository in
            try await repository.respondToFriendRequest(requestID, accept: accept)
            return accept ? SocialText.nowFriends(with: profile.shownName) : SocialText.requestDeclined
        }
    }

    @discardableResult
    public func cancel(_ request: FriendRequest) async -> Bool {
        await cancelRequest(request.id, to: request.profile)
    }

    @discardableResult
    public func cancelRequest(_ requestID: UUID, to profile: SocialProfile) async -> Bool {
        await perform(on: requestID, also: profile.publicID) { repository in
            try await repository.cancelFriendRequest(requestID)
            return SocialText.requestWithdrawn
        }
    }

    @discardableResult
    public func removeFriend(_ profile: SocialProfile) async -> Bool {
        await perform(on: profile.publicID) { repository in
            try await repository.removeFriend(profile.publicID)
            return SocialText.friendRemoved(profile.shownName)
        }
    }

    // MARK: Schutz

    /// Blockiert eine Person (der Server beendet Freundschaft, Anfragen und Einladungen zwischen euch).
    @discardableResult
    public func block(_ profile: SocialProfile) async -> Bool {
        await perform(on: profile.publicID) { repository in
            try await repository.block(profile.publicID)
            return SocialText.blocked(profile.shownName)
        }
    }

    @discardableResult
    public func unblock(_ profile: SocialProfile) async -> Bool {
        await perform(on: profile.publicID) { repository in
            try await repository.unblock(profile.publicID)
            return SocialText.unblocked(profile.shownName)
        }
    }

    /// Meldet eine Person, Nachricht oder Gruppe an das Pace-Team.
    @discardableResult
    public func report(_ target: ReportTarget, reason: ReportReason, details: String?) async -> Bool {
        let trimmed = details?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.flatMap { $0.isEmpty ? nil : String($0.prefix(ReportViewModel.maximumDetailsLength)) }
        return await perform(on: target.busyID, reload: false) { repository in
            try await repository.report(target, reason: reason, details: cleaned)
            return SocialText.reportSent
        }
    }

    // MARK: Gruppen

    @discardableResult
    public func respond(to invitation: GroupInvitation, accept: Bool) async -> Bool {
        await perform(on: invitation.id) { repository in
            do {
                _ = try await repository.respondToInvitation(invitation.id, accept: accept)
            } catch SocialError.notFound where accept {
                // Wiederholte Zusage, nachdem die Antwort der ersten verloren ging: Ist man schon Mitglied, hat der
                // Beitritt geklappt.
                guard try await repository.myGroups().contains(where: { $0.id == invitation.groupID }) else {
                    throw SocialError.notFound
                }
            }
            return accept ? SocialText.joinedGroup(invitation.groupName) : SocialText.invitationDeclined
        }
    }

    /// Tritt einer Gruppe per Einladungscode bei. Gibt die Gruppe zurück oder `nil` bei Fehlern (Text in `notice`).
    public func join(inviteCode: String) async -> GroupSummary? {
        guard let repository else { return nil }
        let code = inviteCode.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard (6...12).contains(code.count) else {
            show(Notice(text: SocialError.invalidInviteCode.message, isError: true))
            return nil
        }
        do {
            let group = try await repository.joinGroup(inviteCode: code)
            show(Notice(text: SocialText.joinedGroup(group.name), isError: false))
            await load()
            return group
        } catch {
            show(Notice(text: SocialText.actionMessage(for: error), isError: true))
            return nil
        }
    }

    /// Erstellt eine Gruppe in der Zeitzone des Geräts (Gruppentag) und lädt eingeladene Freunde ein.
    ///
    /// Danach werden – falls der Server das beim Anlegen noch nicht übernommen hat – fehlende Einladungen nachgeholt,
    /// die gewählte Privatsphäre gesetzt und das Gruppenbild hochgeladen (erst jetzt gibt es die Gruppe, in deren
    /// Ordner es gehört). Klappt einer dieser Schritte nicht, gibt es die Gruppe trotzdem; der Hinweis sagt, was fehlt.
    /// Fehler beim Anlegen selbst stehen in `notice`, die Rückgabe ist dann `nil`.
    public func createGroup(_ draft: GroupDraft, image: GroupImageUpload? = nil) async -> GroupSummary? {
        guard let repository else { return nil }
        guard let name = draft.validName else {
            show(Notice(text: SocialError.invalidName.message, isError: true))
            return nil
        }
        guard let description = draft.validDescription else {
            show(Notice(text: SocialError.invalidDescription.message, isError: true))
            return nil
        }
        guard GroupGoalRules.range.contains(draft.dailyGoal) else {
            show(Notice(text: SocialError.invalidGoal.message, isError: true))
            return nil
        }
        var cleaned = draft
        cleaned.name = name
        cleaned.description = description
        var group: GroupSummary
        do {
            group = try await repository.createGroup(cleaned, timeZone: calendar.timeZone.identifier)
        } catch {
            show(Notice(text: SocialText.actionMessage(for: error), isError: true))
            return nil
        }

        var warnings: [String] = []
        if !cleaned.inviteePublicIDs.isEmpty, await !inviteMissing(cleaned.inviteePublicIDs, to: group.id, repository: repository) {
            warnings.append(SocialText.invitesIncomplete)
        }
        if group.privacy != cleaned.privacy {
            do {
                group = try await repository.updateGroupDetails(
                    group.id, name: group.name, description: group.description, kind: group.kind, privacy: cleaned.privacy
                )
            } catch {
                warnings.append(SocialText.privacyNotSaved)
            }
        }
        if let image {
            if let updated = await uploadGroupImage(image, for: group.id, repository: repository) {
                group = updated
            } else {
                warnings.append(SocialText.imageNotSaved)
            }
        }

        let detail = GroupDetailViewModel(group: group, repository: repository, social: self, media: media)
        groupDetails[group.id] = detail
        let text = ([SocialText.groupCreated(group.name)] + warnings).joined(separator: " ")
        let notice = Notice(text: text, isError: !warnings.isEmpty)
        show(notice)
        // Die Details öffnen sich direkt danach – dort soll stehen, ob etwas fehlt.
        detail.show(notice)
        await load()
        return group
    }

    /// Lädt Freunde ein, deren Einladung nach dem Anlegen noch fehlt. `false`, wenn mindestens eine scheitert.
    private func inviteMissing(_ invitees: [UUID], to groupID: UUID, repository: any SocialRepository) async -> Bool {
        let pending = (try? await repository.outgoingInvitations(for: groupID)) ?? []
        let invited = Set(pending.map(\.profile.publicID))
        var allSent = true
        for invitee in invitees where !invited.contains(invitee) {
            do {
                _ = try await repository.invite(invitee, to: groupID)
            } catch {
                allSent = false
            }
        }
        return allSent
    }

    /// Lädt ein Gruppenbild hoch und setzt es. `nil`, wenn es nicht geklappt hat (oder es keinen Bildspeicher gibt).
    func uploadGroupImage(_ image: GroupImageUpload, for groupID: UUID, repository: any SocialRepository) async -> GroupSummary? {
        guard let media, image.data.count <= Self.groupImageMaximumBytes else { return nil }
        do {
            let reference = try await media.upload(image.data, contentType: image.contentType, to: .groupImage(groupID: groupID))
            return try await repository.setGroupImage(groupID, path: reference.path)
        } catch {
            return nil
        }
    }

    /// Ein Spitzname wurde gespeichert: sofort in Freunden, Ranking (Top-Freunde, Home) und Chats übernehmen; die
    /// Chatliste gleicht sich im Hintergrund mit dem Server ab (Titel, Absendernamen).
    func nicknameDidChange(_ profile: SocialProfile) {
        onNicknameChange?(profile)
        friends = friends.map { friend in
            guard friend.profile.publicID == profile.publicID else { return friend }
            return Friend(profile: friend.profile.withNickname(profile.nickname), friendsSince: friend.friendsSince)
        }
        ranking = ranking.map { entry in
            entry.publicUserID == profile.publicID ? entry.withNickname(profile.nickname) : entry
        }
        // Gespeicherte Gruppendetails und Gruppenkalender kennen den alten Namen – im Hintergrund neu laden.
        let details = Array(groupDetails.values)
        let calendars = Array(groupCalendars.values)
        Task { [chats] in
            await chats.profileDidChange()
            for detail in details {
                await detail.load()
            }
            for calendar in calendars {
                await calendar.load(force: true)
            }
        }
    }

    public func dismissNotice() {
        show(nil)
    }

    // MARK: ViewModels der Unterseiten

    /// ViewModel für die Detailansicht einer Gruppe (dasselbe für Details, Mitglieder und Einstellungen).
    public func detail(for group: GroupSummary) -> GroupDetailViewModel? {
        guard let repository else { return nil }
        if let cached = groupDetails[group.id] { return cached }
        let detail = GroupDetailViewModel(group: group, repository: repository, social: self, media: media)
        groupDetails[group.id] = detail
        return detail
    }

    /// ViewModel einer Gruppe über ihre ID; `nil`, wenn man sie nicht (mehr) kennt.
    public func detail(groupID: UUID) -> GroupDetailViewModel? {
        if let cached = groupDetails[groupID] { return cached }
        guard let group = groups.first(where: { $0.id == groupID }) else { return nil }
        return detail(for: group)
    }

    /// Nach Verlassen oder Löschen: Die nächste Ansicht dieser Gruppe beginnt neu.
    func discardDetail(for groupID: UUID) {
        groupDetails[groupID] = nil
        groupCalendars[groupID] = nil
    }

    /// Gruppenkalender einer Gruppe, in der man Mitglied ist; `nil` ohne Backend bzw. unbekannte Gruppe.
    public func groupCalendar(groupID: UUID) -> GroupCalendarViewModel? {
        guard let repository else { return nil }
        if let cached = groupCalendars[groupID] { return cached }
        guard let group = groups.first(where: { $0.id == groupID }) else { return nil }
        let viewModel = GroupCalendarViewModel(
            groupID: group.id, groupName: group.name, repository: repository, calendar: calendar, now: now
        )
        groupCalendars[groupID] = viewModel
        return viewModel
    }

    /// ViewModel für das Profil eines Freundes (nur Namen und Wettbewerbsschritte).
    public func profile(for friend: SocialProfile) -> FriendProfileViewModel? {
        repository.map { FriendProfileViewModel(profile: friend, repository: $0, social: self, calendar: calendar, now: now) }
    }

    /// ViewModel für das Profil einer beliebigen Person (Freund oder nicht).
    public func userProfile(for profile: SocialProfile) -> UserProfileViewModel? {
        repository.map { UserProfileViewModel(profile: profile, repository: $0, social: self) }
    }

    /// „Freund hinzufügen“: Suche nach Benutzernamen.
    public func friendSearch(debounce: Duration = .milliseconds(350)) -> FriendSearchViewModel? {
        repository.map { FriendSearchViewModel(repository: $0, social: self, debounce: debounce) }
    }

    /// Formular „Gruppe erstellen“.
    public func createGroupForm() -> CreateGroupViewModel {
        CreateGroupViewModel(social: self)
    }

    /// Empfängerauswahl „Profil teilen“.
    public func shareProfile(_ profile: SocialProfile) -> ShareProfileViewModel {
        ShareProfileViewModel(profile: profile, social: self)
    }

    /// Meldung einer Person oder Gruppe.
    public func reportForm(_ subject: SocialReportSubject) -> ReportViewModel {
        ReportViewModel(subject: subject, social: self)
    }

    /// Social-Einstellungen (blockierte Nutzer).
    public func settings() -> SocialSettingsViewModel {
        SocialSettingsViewModel(repository: repository, social: self)
    }

    /// Vollständiges Freundesranking (heute oder diese Woche).
    public func friendsRanking() -> FriendsRankingViewModel {
        FriendsRankingViewModel(repository: repository, social: self)
    }

    // MARK: Hilfen

    /// Hinweis einer Aktion. Er ersetzt einen offenen Ladefehler-Hinweis und wird von einem späteren erfolgreichen
    /// Laden nicht entfernt (auch nicht, wenn sein Text zufällig gleich ist).
    func show(_ notice: Notice?) {
        self.notice = notice
        loadErrorNotice = nil
    }

    /// Führt eine Aktion für eine Person, Anfrage oder Einladung aus. Während sie läuft, ist die ID (und `also`)
    /// gesperrt; danach steht das Ergebnis in `notice`, und der Stand wird neu geladen.
    @discardableResult
    private func perform(
        on id: UUID,
        also otherID: UUID? = nil,
        reload: Bool = true,
        _ action: (any SocialRepository) async throws -> String
    ) async -> Bool {
        guard let repository, !busyIDs.contains(id) else { return false }
        busyIDs.insert(id)
        if let otherID { busyIDs.insert(otherID) }
        defer {
            busyIDs.remove(id)
            if let otherID { busyIDs.remove(otherID) }
        }
        do {
            let text = try await action(repository)
            show(Notice(text: text, isError: false))
            if reload { await load() }
            return true
        } catch {
            show(Notice(text: SocialText.actionMessage(for: error), isError: true))
            if reload { await load() }
            return false
        }
    }

    static func message(for error: any Error) -> String {
        SocialText.message(for: error)
    }
}

extension ReportTarget {
    /// Sperr-ID, solange die Meldung läuft.
    var busyID: UUID {
        switch self {
        case .user(let publicID): publicID
        case .message(let id): id
        case .group(let id): id
        }
    }
}

/// Grenzen für das Gruppentagesziel (wie auf dem Server: 1.000 bis 100.000 Schritte).
public enum GroupGoalRules {
    public static let range = 1_000...100_000
    public static let increment = 500
    public static let defaultGoal = 8_000
    /// Schnellauswahl in der Zielauswahl.
    public static let presets = [5_000, 6_000, 8_000, 10_000, 12_000, 15_000]

    /// Ziel im erlaubten Bereich, auf 500er-Schritte gerundet.
    public static func clamped(_ goal: Int) -> Int {
        let bounded = min(max(goal, range.lowerBound), range.upperBound)
        return (bounded + increment / 2) / increment * increment
    }
}
