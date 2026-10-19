import Foundation
import Observation
import PaceCore

/// Ziel beim Öffnen eines Chats: eine vorhandene Unterhaltung, der direkte Chat mit einem Freund oder der Chat einer
/// Gruppe.
public enum ChatTarget: Hashable, Sendable {
    case conversation(id: UUID, kind: ConversationKind, title: String)
    case direct(SocialProfile)
    case group(id: UUID, name: String)

    /// Name für die Kopfzeile, solange die Unterhaltung noch nicht geladen ist.
    public var title: String {
        switch self {
        case .conversation(_, _, let title): title
        case .direct(let profile): profile.displayName
        case .group(_, let name): name
        }
    }

    public var kind: ConversationKind {
        switch self {
        case .conversation(_, let kind, _): kind
        case .direct: .direct
        case .group: .group
        }
    }

    /// Ziel für eine Zeile der Chatliste.
    public init(_ conversation: ConversationSummary) {
        self = .conversation(id: conversation.id, kind: conversation.kind, title: conversation.title)
    }
}

/// Chatliste im Social-Tab (Filter Alle/Freunde/Gruppen) und Erzeugung der einzelnen Chats.
///
/// Lädt die Unterhaltungen über `ChatRepository`, hält sie per Echtzeit-Ereignis und – als Rückfall – regelmäßig
/// aktuell, solange die Liste sichtbar ist (``observe()``), und liefert je Unterhaltung immer dasselbe
/// ``ChatViewModel``, damit Verlauf und Entwurf beim Zurücknavigieren erhalten bleiben.
@MainActor
@Observable
public final class ChatListViewModel {
    public enum Filter: String, CaseIterable, Sendable, Identifiable {
        case all
        case friends
        case groups

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .all: PaceLocalization.text(de: "Alle", en: "All", ru: "Все")
            case .friends: PaceLocalization.text(de: "Freunde", en: "Friends", ru: "Друзья")
            case .groups: PaceLocalization.text(de: "Gruppen", en: "Groups", ru: "Группы")
            }
        }

        public func includes(_ conversation: ConversationSummary) -> Bool {
            switch self {
            case .all: true
            case .friends: conversation.kind == .direct
            case .groups: conversation.kind == .group
            }
        }
    }

    public enum State: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
        /// Ohne Backend bzw. Chats auf dem Server noch nicht eingerichtet.
        case unavailable(String)
    }

    public var filter: Filter = .all
    /// Alle Unterhaltungen, neueste zuerst.
    public private(set) var conversations: [ConversationSummary] = []
    public private(set) var state: State = .idle
    /// Das letzte Aktualisieren ist fehlgeschlagen; die zuletzt geladenen Chats bleiben sichtbar.
    public private(set) var refreshError: String?

    @ObservationIgnored let repository: (any ChatRepository)?
    @ObservationIgnored let media: (any MediaRepository)?
    /// Gruppen, Blockieren und Melden; `nil`, wenn nicht verdrahtet (dann ohne Gruppenkopf und Moderation).
    @ObservationIgnored let social: (any SocialRepository)?
    @ObservationIgnored let calendar: ActivityCalendar
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored let pollInterval: Duration
    @ObservationIgnored let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var reloadRequested = false
    @ObservationIgnored private var lastLoadedAt: Date?
    @ObservationIgnored private var chats: [ChatViewModel] = []

    /// - Parameters:
    ///   - repository: `nil`, wenn kein Backend konfiguriert ist.
    ///   - media: Hochladen und Laden von Bildern und GIFs.
    ///   - social: Gruppen (Kopf des Gruppenchats), blockierte Personen, Blockieren und Melden.
    ///   - pollInterval: Abstand der regelmäßigen Aktualisierung, solange Liste bzw. Chat sichtbar sind.
    ///   - sleep: Wartet zwischen zwei Aktualisierungen (in Tests steuerbar).
    public init(
        repository: (any ChatRepository)?,
        media: (any MediaRepository)?,
        social: (any SocialRepository)? = nil,
        calendar: ActivityCalendar = ActivityCalendar(),
        now: @escaping @Sendable () -> Date = { Date() },
        pollInterval: Duration = .seconds(25),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.repository = repository
        self.media = media
        self.social = social
        self.calendar = calendar
        self.now = now
        self.pollInterval = pollInterval
        self.sleep = sleep
        if repository == nil {
            state = .unavailable(ChatTexts.unavailable)
        }
    }

    public var isAvailable: Bool {
        if case .unavailable = state { return false }
        return repository != nil
    }

    /// Ungelesene Nachrichten über alle Unterhaltungen.
    public var unreadCount: Int {
        conversations.reduce(0) { $0 + $1.unreadCount }
    }

    /// Unterhaltungen des gewählten Filters.
    public var filteredConversations: [ConversationSummary] {
        conversations.filter(filter.includes)
    }

    /// Lokale Suche (Suchfeld der Social-Hauptseite): Name des Chats bzw. Benutzername des Freundes, ohne Rücksicht
    /// auf Groß-/Kleinschreibung und Akzente. Leere Suche liefert alle.
    public func conversations(matching query: String) -> [ConversationSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return conversations }
        let username = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return conversations.filter { conversation in
            if conversation.title.range(of: trimmed, options: options) != nil { return true }
            guard let peer = conversation.peer, !username.isEmpty else { return false }
            return peer.username.range(of: username, options: options) != nil
                || peer.displayName.range(of: trimmed, options: options) != nil
        }
    }

    /// Angezeigte Zeilen: Suche und Filter kombiniert.
    public func displayedConversations(searchText: String) -> [ConversationSummary] {
        conversations(matching: searchText).filter(filter.includes)
    }

    // MARK: Laden

    /// Lädt beim ersten Erscheinen bzw. wenn der Stand älter als 20 Sekunden ist.
    public func loadIfNeeded() async {
        if state == .loaded, let lastLoadedAt, now().timeIntervalSince(lastLoadedAt) < 20 { return }
        await load(fresh: false)
    }

    /// Lädt die Unterhaltungen. Läuft schon ein Ladevorgang, wartet der Aufruf auf einen Stand, der erst danach
    /// abgefragt wird; mehrere solche Aufrufe teilen sich einen zusätzlichen Ladevorgang (keine parallelen Abfragen).
    public func load() async {
        await load(fresh: true)
    }

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
        do {
            let loaded = try await repository.conversations()
            conversations = loaded.sorted { lhs, rhs in
                lhs.updatedAt == rhs.updatedAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.updatedAt > rhs.updatedAt
            }
            state = .loaded
            refreshError = nil
            lastLoadedAt = now()
            for chat in chats {
                chat.updateSummary(from: conversations)
            }
        } catch is CancellationError {
            if state == .loading { state = .idle }
        } catch let error as SocialError where error == .unavailable {
            state = .unavailable(error.message)
        } catch {
            if state == .loaded {
                refreshError = ChatTexts.message(for: error)
            } else {
                state = .failed(ChatTexts.message(for: error))
            }
        }
    }

    /// Hält die Liste aktuell, solange die aufrufende Ansicht sichtbar ist (`.task { await viewModel.observe() }`):
    /// erstes Laden, Echtzeit-Ereignisse und als Rückfall eine regelmäßige Abfrage. Endet, wenn die Aufgabe
    /// abgebrochen wird.
    public func observe() async {
        guard let repository else { return }
        await loadIfNeeded()
        let interval = pollInterval
        let sleep = sleep
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                for await _ in repository.conversationEvents() {
                    await self?.load()
                }
            }
            group.addTask { [weak self] in
                while !Task.isCancelled {
                    do {
                        try await sleep(interval)
                    } catch {
                        return
                    }
                    await self?.load()
                }
            }
            await group.waitForAll()
        }
    }

    // MARK: Rückmeldungen der Chats

    /// Ein Chat wurde gelesen: Zähler sofort zurücksetzen (der Server hat den Lesestand schon gespeichert).
    func didMarkRead(_ conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        guard conversations[index].unreadCount != 0 else { return }
        conversations[index] = conversations[index].replacing(unreadCount: 0)
    }

    /// In einem Chat hat sich etwas geändert (gesendet, gelöscht, blockiert): Liste im Hintergrund neu laden.
    func conversationDidChange() {
        guard repository != nil else { return }
        Task { await self.load() }
    }

    // MARK: Chats

    /// ViewModel für einen einzelnen Chat. Für dieselbe Unterhaltung – egal ob über die Liste, ein Profil oder eine
    /// Gruppe geöffnet – gibt es immer dieselbe Instanz.
    public func chat(for target: ChatTarget) -> ChatViewModel {
        if let existing = chats.first(where: { $0.matches(target) }) {
            return existing
        }
        let known = knownConversation(for: target)
        if let known, let existing = chats.first(where: { $0.matches(.conversation(id: known.id, kind: known.kind, title: known.title)) }) {
            return existing
        }
        let chat = ChatViewModel(
            target: target,
            conversation: known,
            repository: repository,
            media: media,
            social: social,
            calendar: calendar,
            now: now,
            pollInterval: pollInterval,
            sleep: sleep,
            list: self
        )
        chats.append(chat)
        return chat
    }

    /// Bereits geladene Unterhaltung zu einem Ziel.
    func knownConversation(for target: ChatTarget) -> ConversationSummary? {
        switch target {
        case .conversation(let id, _, _):
            conversations.first { $0.id == id }
        case .direct(let profile):
            conversations.first { $0.kind == .direct && $0.peer?.publicID == profile.publicID }
        case .group(let id, _):
            conversations.first { $0.kind == .group && $0.groupID == id }
        }
    }

    // MARK: Profil teilen

    /// Teilt ein Profil als Profilnachricht in die gewählten Chats (Freunde und eigene Gruppen).
    ///
    /// Für jedes Ziel wird die Unterhaltung geöffnet bzw. geholt und eine Nachricht vom Typ `profile` gesendet. Schlägt
    /// das bei einzelnen Zielen fehl, wird bei den anderen trotzdem gesendet und danach ``ProfileShareError`` mit den
    /// fehlgeschlagenen Zielen geworfen.
    public func shareProfile(_ profile: SocialProfile, with targets: [ChatTarget]) async throws {
        guard let repository, isAvailable else { throw SocialError.unavailable }
        var seen = Set<ChatTarget>()
        let unique = targets.filter { seen.insert($0).inserted }
        guard !unique.isEmpty else { return }
        var failures: [ProfileShareError.Failure] = []
        for target in unique {
            do {
                let conversationID = try await conversationID(for: target, repository: repository)
                _ = try await repository.send(ChatMessageDraft(kind: .profile, sharedProfileID: profile.publicID), to: conversationID)
            } catch {
                failures.append(ProfileShareError.Failure(target: target, message: ChatTexts.message(for: error)))
            }
        }
        await load()
        if !failures.isEmpty {
            throw ProfileShareError(failures: failures, sharedCount: unique.count - failures.count)
        }
    }

    private func conversationID(for target: ChatTarget, repository: any ChatRepository) async throws -> UUID {
        if let known = knownConversation(for: target) {
            return known.id
        }
        switch target {
        case .conversation(let id, _, _):
            return id
        case .direct(let profile):
            return try await repository.openDirectConversation(with: profile.publicID).id
        case .group(let id, _):
            return try await repository.groupConversation(for: id).id
        }
    }
}
