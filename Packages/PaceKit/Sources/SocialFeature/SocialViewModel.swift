import Foundation
import Observation
import PaceCore

/// Der Social-Bereich: Freunde suchen und hinzufügen, Anfragen, Freundesranking, Gruppen und Einladungen.
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

    public enum SearchState: Equatable {
        case idle
        case searching
        case found(ProfileSearchResult)
        case notFound(String)
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var friends: [Friend] = []
    public private(set) var requests: [FriendRequest] = []
    /// Du und deine Freunde, heute.
    public private(set) var ranking: [LeaderboardEntry] = []
    public private(set) var groups: [GroupSummary] = []
    public private(set) var invitations: [GroupInvitation] = []

    public var searchText = ""
    public private(set) var search: SearchState = .idle
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

    @ObservationIgnored private let repository: (any SocialRepository)?
    @ObservationIgnored private let calendar: ActivityCalendar
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let ownUsername: @MainActor () -> String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Während eines Ladevorgangs wurde ein frischer Stand verlangt (z. B. nach einer Aktion).
    @ObservationIgnored private var reloadRequested = false
    @ObservationIgnored private var lastLoadedAt: Date?
    /// Der Hinweis des letzten fehlgeschlagenen Ladens – verschwindet, sobald wieder erfolgreich geladen wurde.
    @ObservationIgnored private var loadErrorNotice: Notice?

    /// - Parameters:
    ///   - repository: `nil`, wenn kein Backend konfiguriert ist.
    ///   - ownUsername: Eigener Benutzername zum Teilen.
    public init(
        repository: (any SocialRepository)?,
        ownUsername: @escaping @MainActor () -> String? = { nil },
        calendar: ActivityCalendar = ActivityCalendar(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.ownUsername = ownUsername
        self.calendar = calendar
        self.now = now
        if repository == nil {
            state = .unavailable(SocialError.unavailable.message)
        }
    }

    public var isAvailable: Bool {
        if case .unavailable = state { return false }
        return repository != nil
    }

    public var incomingRequests: [FriendRequest] { requests.filter { $0.direction == .incoming } }
    public var outgoingRequests: [FriendRequest] { requests.filter { $0.direction == .outgoing } }

    /// z. B. `@niklas` zum Weitergeben.
    public var shareText: String? {
        ownUsername().map { "Füge mich in Pace hinzu – mein Benutzername: @\($0)" }
    }

    public var username: String? {
        ownUsername().map { "@\($0)" }
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
        let today = calendar.day(containing: now())
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
                let notice = Notice(text: Self.message(for: error), isError: true)
                self.notice = notice
                loadErrorNotice = notice
            } else {
                state = .failed(Self.message(for: error))
            }
        }
    }

    // MARK: Suche

    /// Sucht eine Person über ihren genauen Benutzernamen (ohne @, Groß-/Kleinschreibung egal).
    public func searchProfile() async {
        guard let repository else { return }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard UsernameRules.violation(for: query) == nil else {
            search = .notFound("Benutzernamen bestehen aus 3–20 Buchstaben, Ziffern oder Unterstrichen.")
            return
        }
        search = .searching
        do {
            if let result = try await repository.findProfile(username: query) {
                search = .found(result)
            } else {
                search = .notFound("Niemand mit dem Benutzernamen @\(query) gefunden.")
            }
        } catch {
            search = .failed(Self.message(for: error))
        }
    }

    public func clearSearch() {
        searchText = ""
        search = .idle
    }

    // MARK: Freunde

    public func sendRequest(to profile: SocialProfile) async {
        await perform(on: profile.publicID) { repository in
            let outcome = try await repository.sendFriendRequest(to: profile.publicID)
            switch outcome {
            case .requested: return "Anfrage an \(profile.displayName) gesendet."
            case .accepted: return "Du und \(profile.displayName) seid jetzt befreundet."
            case .alreadyFriends: return "Ihr seid bereits befreundet."
            case .alreadyRequested: return "Du hast bereits eine Anfrage gesendet."
            }
        }
        await refreshSearch()
    }

    public func respond(to request: FriendRequest, accept: Bool) async {
        await perform(on: request.id) { repository in
            try await repository.respondToFriendRequest(request.id, accept: accept)
            return accept ? "Du und \(request.profile.displayName) seid jetzt befreundet." : "Anfrage abgelehnt."
        }
        await refreshSearch()
    }

    public func cancel(_ request: FriendRequest) async {
        await perform(on: request.id) { repository in
            try await repository.cancelFriendRequest(request.id)
            return "Anfrage zurückgezogen."
        }
        await refreshSearch()
    }

    public func removeFriend(_ profile: SocialProfile) async {
        await perform(on: profile.publicID) { repository in
            try await repository.removeFriend(profile.publicID)
            return "\(profile.displayName) ist nicht mehr in deinen Freunden."
        }
    }

    // MARK: Gruppen

    public func respond(to invitation: GroupInvitation, accept: Bool) async {
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
            return accept ? "Du bist „\(invitation.groupName)“ beigetreten." : "Einladung abgelehnt."
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
            show(Notice(text: "Du bist „\(group.name)“ beigetreten.", isError: false))
            await load()
            return group
        } catch {
            show(Notice(text: Self.message(for: error), isError: true))
            return nil
        }
    }

    /// Erstellt eine Gruppe in der Zeitzone des Geräts (Gruppentag). Fehler stehen in `notice`.
    public func createGroup(_ draft: GroupDraft) async -> GroupSummary? {
        guard let repository else { return nil }
        guard let name = draft.validName else {
            show(Notice(text: SocialError.invalidName.message, isError: true))
            return nil
        }
        guard let description = draft.validDescription else {
            show(Notice(text: SocialError.invalidDescription.message, isError: true))
            return nil
        }
        var cleaned = draft
        cleaned.name = name
        cleaned.description = description
        do {
            let group = try await repository.createGroup(cleaned, timeZone: calendar.timeZone.identifier)
            show(Notice(text: "Gruppe „\(group.name)“ erstellt.", isError: false))
            await load()
            return group
        } catch {
            show(Notice(text: Self.message(for: error), isError: true))
            return nil
        }
    }

    public func dismissNotice() {
        show(nil)
    }

    /// ViewModel für die Detailansicht einer Gruppe.
    public func detail(for group: GroupSummary) -> GroupDetailViewModel? {
        repository.map { GroupDetailViewModel(group: group, repository: $0, social: self) }
    }

    /// ViewModel für das Profil eines Freundes.
    public func profile(for friend: SocialProfile) -> FriendProfileViewModel? {
        repository.map { FriendProfileViewModel(profile: friend, repository: $0, social: self, calendar: calendar, now: now) }
    }

    // MARK: Hilfen

    /// Hinweis einer Aktion. Er ersetzt einen offenen Ladefehler-Hinweis und wird von einem späteren erfolgreichen
    /// Laden nicht entfernt (auch nicht, wenn sein Text zufällig gleich ist).
    private func show(_ notice: Notice?) {
        self.notice = notice
        loadErrorNotice = nil
    }

    private func perform(on id: UUID, _ action: (any SocialRepository) async throws -> String) async {
        guard let repository, !busyIDs.contains(id) else { return }
        busyIDs.insert(id)
        defer { busyIDs.remove(id) }
        do {
            let text = try await action(repository)
            show(Notice(text: text, isError: false))
            await load()
        } catch {
            show(Notice(text: Self.message(for: error), isError: true))
            await load()
        }
    }

    /// Nach einer Aktion den Suchtreffer aktualisieren (z. B. „Anfrage gesendet“).
    private func refreshSearch() async {
        guard case .found = search else { return }
        await searchProfile()
    }

    static func message(for error: any Error) -> String {
        (error as? SocialError)?.message ?? SocialError.unexpected("").message
    }
}
