import Foundation
import Observation
import PaceCore

/// Ein einzelner Chat (privat oder Gruppe, Referenzbild 5).
///
/// Lädt den Verlauf seitenweise über `ChatRepository`, zeigt eigene Nachrichten sofort an (optimistisch, mit Status
/// „wird gesendet“/„fehlgeschlagen“) und gleicht sie über die `clientID` mit dem Server ab, damit eine Nachricht nie
/// doppelt erscheint – egal ob sie über die Antwort des Sendens, ein Echtzeit-Ereignis oder ein Neuladen ankommt.
/// Solange der Chat sichtbar ist (``observe()``), hält er sich per Echtzeit und – als Rückfall – regelmäßig aktuell
/// und markiert neue Nachrichten als gelesen.
@MainActor
@Observable
public final class ChatViewModel {
    public enum State: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
        /// Ohne Backend bzw. Chats auf dem Server noch nicht eingerichtet.
        case unavailable(String)
    }

    public let target: ChatTarget
    /// Die Unterhaltung, sobald sie bekannt ist (Schreibrecht, Gegenüber, Gruppe).
    public private(set) var conversation: ConversationSummary?
    public private(set) var state: State = .idle
    /// Nachrichten vom Server, chronologisch aufsteigend.
    public private(set) var messages: [ChatMessage] = []
    /// Eigene Nachrichten, die noch gesendet werden oder fehlgeschlagen sind.
    public private(set) var pending: [PendingChatMessage] = []
    /// Es gibt (vermutlich) ältere Nachrichten, die beim Hochscrollen nachgeladen werden.
    public private(set) var hasOlderMessages = false
    public private(set) var isLoadingOlder = false
    public private(set) var olderError: String?
    /// Das letzte Aktualisieren ist fehlgeschlagen; der bisherige Verlauf bleibt sichtbar.
    public private(set) var refreshError: String?
    /// Rückmeldung der letzten Aktion (z. B. „Nachricht gelöscht“ oder ein Fehler beim Bild).
    public private(set) var notice: ChatNotice?
    /// Gruppe (Kopf mit Streak) bei Gruppenchats, sobald geladen.
    public private(set) var group: GroupSummary?
    /// Mitglieder der Gruppe (Avatarreihe), sobald geladen.
    public private(set) var members: [SocialProfile] = []
    /// Personen, die du blockiert hast – ihre Nachrichten in Gruppen erscheinen eingeklappt.
    public private(set) var blockedUserIDs: Set<UUID> = []
    /// Eingeklappte Nachrichten blockierter Personen, die du bewusst aufgedeckt hast.
    public private(set) var revealedMessageIDs: Set<UUID> = []
    /// Nachrichten, für die gerade eine Aktion läuft (Löschen, Melden).
    public private(set) var busyMessageIDs: Set<UUID> = []
    /// Eine Aktion für die ganze Unterhaltung läuft (Blockieren, Melden).
    public private(set) var isPerformingAction = false
    /// Text im Eingabefeld – bleibt beim Zurücknavigieren erhalten (gleiche Instanz je Unterhaltung).
    public var draftText = ""
    /// Nachricht, auf die die nächste geantwortet wird (Vorschau über der Eingabe).
    public private(set) var replyingTo: ChatMessage?
    /// Eigene Textnachricht, die gerade bearbeitet wird (ihr Text steht im Eingabefeld).
    public private(set) var editingMessage: ChatMessage?
    /// Angepinnte Nachrichten, zuletzt angepinnte zuerst.
    public private(set) var pins: [ChatPin] = []
    /// Index des Pins, den der Hinweis oben zeigt (Antippen springt hin und zeigt danach den nächsten).
    public private(set) var pinIndex = 0
    /// Sprung zu einer Nachricht (Antwort-Verweis, Pin, Favorit): Die Ansicht scrollt hin und hebt sie kurz hervor.
    public private(set) var jumpRequest: ChatJumpRequest?
    /// Eigene Favoriten dieser Unterhaltung (Chat-Einstellungen).
    public private(set) var favorites: ChatFavoritesState = .idle

    @ObservationIgnored let repository: (any ChatRepository)?
    @ObservationIgnored let media: (any MediaRepository)?
    @ObservationIgnored let social: (any SocialRepository)?
    @ObservationIgnored let calendar: ActivityCalendar
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored let pollInterval: Duration
    @ObservationIgnored let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private weak var list: ChatListViewModel?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshRequested = false
    @ObservationIgnored private var olderTask: Task<Void, Never>?
    /// Bis hierhin ist der Lesestand an den Server gemeldet.
    @ObservationIgnored private var lastReadMark: Date?
    /// Anzahl laufender ``observe()``-Aufrufe (beim schnellen Wechsel kann ein alter kurz neben dem neuen laufen).
    @ObservationIgnored private var observerCount = 0
    /// Der Chat ist gerade auf dem Bildschirm (dann kein Hinweis auf neue Nachrichten).
    var isVisible: Bool { observerCount > 0 }
    /// Gerade hochgeladene Bilder und Sprachnachrichten (Pfad → Daten), damit sie nicht noch einmal geladen werden
    /// müssen.
    @ObservationIgnored private var uploadedMedia: [String: Data] = [:]
    /// Entwurf vor dem Bearbeiten – kommt nach Speichern oder Abbrechen zurück ins Eingabefeld.
    @ObservationIgnored private var draftBeforeEditing: String?

    init(
        target: ChatTarget,
        conversation: ConversationSummary? = nil,
        repository: (any ChatRepository)?,
        media: (any MediaRepository)?,
        social: (any SocialRepository)? = nil,
        calendar: ActivityCalendar = ActivityCalendar(),
        now: @escaping @Sendable () -> Date = { Date() },
        pollInterval: Duration = .seconds(25),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        list: ChatListViewModel? = nil
    ) {
        self.target = target
        self.conversation = conversation
        self.repository = repository
        self.media = media
        self.social = social
        self.calendar = calendar
        self.now = now
        self.pollInterval = pollInterval
        self.sleep = sleep
        self.list = list
        if repository == nil {
            state = .unavailable(ChatTexts.unavailable)
        }
    }

    // MARK: Anzeige

    public var kind: ConversationKind {
        conversation?.kind ?? target.kind
    }

    /// Gruppenname bzw. Name des Freundes.
    public var title: String {
        if let group { return group.name }
        if let conversation { return conversation.shownTitle }
        return target.title
    }

    /// Gesprächspartner bei Privatchats.
    public var peer: SocialProfile? {
        if let peer = conversation?.peer { return peer }
        if case .direct(let profile) = target { return profile }
        return nil
    }

    public var groupID: UUID? {
        if let groupID = conversation?.groupID { return groupID }
        if case .group(let id, _) = target { return id }
        return group?.id
    }

    public var memberCount: Int {
        group?.memberCount ?? conversation?.memberCount ?? members.count
    }

    /// Höchstens sechs Mitglieder für die Avatarreihe (Referenzbild 5); der Rest ist über „+“ bzw. die Mitgliederliste
    /// erreichbar.
    public var memberPreview: [SocialProfile] {
        Array(members.prefix(6))
    }

    /// „+“ in der Avatarreihe: Mitglieder können Freunde einladen (der Server prüft das Recht).
    public var canInvite: Bool {
        group != nil && canSend
    }

    /// In dieser Unterhaltung kann geschrieben werden.
    public var canSend: Bool {
        guard state == .loaded, let conversation else { return false }
        if let peer = conversation.peer, blockedUserIDs.contains(peer.publicID) { return false }
        return conversation.canSend
    }

    /// Erklärung statt Eingabeleiste, wenn nicht (mehr) geschrieben werden kann.
    public var readOnlyMessage: String? {
        guard state == .loaded, conversation != nil, !canSend else { return nil }
        let blockedByMe = peer.map { blockedUserIDs.contains($0.publicID) } ?? false
        return ChatTexts.readOnly(kind: kind, peerName: peer?.shownName, blockedByMe: blockedByMe)
    }

    /// Senden-Knopf aktiv: Text vorhanden und nicht zu lang.
    public var canSubmitText: Bool {
        canSend && ChatRules.validText(draftText) != nil
    }

    /// Der Entwurf ist länger als erlaubt.
    public var isDraftTooLong: Bool {
        draftText.count > ChatRules.maximumTextLength
    }

    /// Verbleibende Zeichen, sobald es knapp wird (ab 90 % der Höchstlänge), sonst `nil`.
    public var remainingCharacters: Int? {
        let remaining = ChatRules.maximumTextLength - draftText.count
        return remaining <= ChatRules.maximumTextLength / 10 ? remaining : nil
    }

    /// Verlauf mit Tages-Trennern und Nachrichtenblöcken.
    public var timeline: [ChatTimelineItem] {
        ChatTimeline.build(
            messages: messages,
            pending: pending,
            kind: kind,
            blockedUserIDs: blockedUserIDs,
            revealedMessageIDs: revealedMessageIDs,
            calendar: calendar,
            now: now()
        )
    }

    /// ID des untersten Eintrags im Verlauf (zum Mitscrollen bei neuen Nachrichten).
    public var lastEntryID: String? {
        if let pendingMessage = pending.max(by: { $0.createdAt < $1.createdAt }) {
            return "pending-\(pendingMessage.clientID.uuidString)"
        }
        return messages.last.map { "message-\($0.id.uuidString)" }
    }

    /// Ob der unterste Eintrag eine eigene Nachricht ist (dann scrollt der Verlauf immer mit).
    public var lastEntryIsOwn: Bool {
        if !pending.isEmpty { return true }
        return messages.last?.isOwn ?? false
    }

    /// Streak-Zeile der Gruppe („12 Tage Streak“) und Stand von heute („Flamme gesichert“).
    public var streakTitle: String? {
        group.map { ChatFormatting.streakTitle($0.currentStreak) }
    }

    public var streakStatus: String? {
        group.map { ChatFormatting.streakStatus(reached: $0.todayReachedCount, required: $0.todayRequiredCount, complete: $0.todayComplete) }
    }

    /// Uhrzeit einer Nachricht in der App-Sprache.
    public func time(of date: Date) -> String {
        ChatFormatting.time(date, calendar: calendar)
    }

    /// Daten eines gerade hochgeladenen Bilds (vermeidet eine zweite Übertragung für die Vorschau).
    public func uploadedData(for reference: MediaReference) -> Data? {
        guard reference.bucket == .chatMedia else { return nil }
        return uploadedMedia[reference.path]
    }

    /// Audiodaten einer Sprachnachricht: gerade aufgenommen (ohne Übertragung) oder vom Server (mit Berechtigungs-
    /// prüfung); `nil`, wenn sie nicht geladen werden konnten.
    public func voiceData(for message: ChatMessage) async -> Data? {
        guard message.kind == .voice, let reference = message.media else { return nil }
        if let cached = uploadedMedia[reference.path] { return cached }
        guard let media, let data = try? await media.data(for: reference) else { return nil }
        uploadedMedia[reference.path] = data
        return data
    }

    public func dismissNotice() {
        notice = nil
    }

    // MARK: Laden

    /// Lädt beim ersten Öffnen bzw. nach einem Fehler.
    public func loadIfNeeded() async {
        switch state {
        case .idle, .failed, .loading: await load()
        case .loaded, .unavailable: break
        }
    }

    /// Lädt Unterhaltung, neueste Nachrichten und – bei Gruppen – den Gruppenkopf. Mehrere gleichzeitige Aufrufe teilen
    /// sich einen Ladevorgang.
    public func load() async {
        guard repository != nil else { return }
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task {
            await self.performLoad()
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
            let summary = try await resolveConversation(repository: repository)
            conversation = summary
            let latest = try await repository.messages(in: summary.id, before: nil, limit: ChatRules.pageSize)
            applyLatestPage(latest)
            state = .loaded
            refreshError = nil
            await loadContext()
            await loadPins()
            await markReadIfNeeded()
        } catch is CancellationError {
            if state == .loading { state = .idle }
        } catch let error as SocialError where error == .unavailable {
            state = .unavailable(error.message)
        } catch let error as SocialError where error == .notFound || error == .notAllowed {
            state = .failed(ChatTexts.conversationGone)
        } catch {
            if state == .loaded {
                refreshError = ChatTexts.message(for: error)
            } else {
                state = .failed(ChatTexts.message(for: error))
            }
        }
    }

    /// Unterhaltung zum Ziel: bereits bekannt, aus der Chatliste, oder vom Server (öffnet ggf. den direkten Chat).
    private func resolveConversation(repository: any ChatRepository) async throws -> ConversationSummary {
        if let conversation { return conversation }
        if let known = list?.knownConversation(for: target) { return known }
        switch target {
        case .conversation(let id, _, _):
            guard let found = try await repository.conversations().first(where: { $0.id == id }) else {
                throw SocialError.notFound
            }
            return found
        case .direct(let profile):
            return try await repository.openDirectConversation(with: profile.publicID)
        case .group(let id, _):
            return try await repository.groupConversation(for: id)
        }
    }

    /// Gruppenkopf (Streak, Mitglieder) und blockierte Personen. Fehler hier verhindern den Chat nicht – der Kopf
    /// zeigt dann nur, was die Unterhaltung selbst weiß.
    private func loadContext() async {
        guard let social else { return }
        if let blocked = try? await social.blockedUsers() {
            blockedUserIDs = Set(blocked.map(\.publicID))
        }
        guard kind == .group, let groupID else { return }
        if let loaded = try? await social.group(groupID) {
            group = loaded
        }
        if let ranking = try? await social.groupRanking(groupID, period: .daily) {
            // Reihenfolge wie im heutigen Gruppenranking (aktivste zuerst).
            members = ranking.entries.map(\.profile)
        }
    }

    /// Neueste Seite übernehmen: Nachrichten im abgedeckten Zeitraum ersetzen (so verschwinden auch anderswo gelöschte
    /// Nachrichten), ältere bereits geladene behalten.
    private func applyLatestPage(_ latest: [ChatMessage]) {
        let sorted = latest.sorted(by: ChatTimeline.chronological)
        if sorted.count < ChatRules.pageSize {
            // Die Seite enthält den ganzen Verlauf.
            messages = sorted
            hasOlderMessages = false
        } else if let first = sorted.first {
            let kept = messages.filter { $0.sentAt < first.sentAt }
            if kept.isEmpty {
                hasOlderMessages = true
            }
            messages = kept + sorted
        }
        removeDeliveredPending()
    }

    /// Weitere Nachrichten übernehmen (ohne Duplikate: gleiche `id` wird ersetzt).
    private func merge(_ incoming: [ChatMessage]) {
        guard !incoming.isEmpty else { return }
        var byID: [UUID: ChatMessage] = [:]
        for message in messages { byID[message.id] = message }
        for message in incoming { byID[message.id] = message }
        messages = byID.values.sorted(by: ChatTimeline.chronological)
        removeDeliveredPending()
    }

    /// Ausstehende Nachrichten, die inzwischen vom Server kommen, nicht doppelt zeigen.
    private func removeDeliveredPending() {
        let delivered = Set(messages.compactMap(\.clientID))
        guard pending.contains(where: { delivered.contains($0.clientID) }) else { return }
        pending.removeAll { delivered.contains($0.clientID) }
    }

    /// Aktualisiert die neueste Seite (Echtzeit-Ereignis, Polling, Zurückkehren). Läuft schon eine Aktualisierung,
    /// folgt genau eine weitere danach – keine parallelen Abfragen.
    public func refresh() async {
        guard repository != nil else { return }
        guard state == .loaded else {
            await loadIfNeeded()
            return
        }
        if let refreshTask {
            refreshRequested = true
            await refreshTask.value
            return
        }
        let task = Task {
            repeat {
                self.refreshRequested = false
                await self.performRefresh()
            } while self.refreshRequested
            self.refreshTask = nil
        }
        refreshTask = task
        await task.value
    }

    private func performRefresh() async {
        guard let repository, let conversation else { return }
        do {
            let latest = try await repository.messages(in: conversation.id, before: nil, limit: ChatRules.pageSize)
            applyLatestPage(latest)
            refreshError = nil
            await markReadIfNeeded()
        } catch is CancellationError {
            return
        } catch let error as SocialError where error == .notFound || error == .notAllowed {
            self.conversation = conversation.replacing(canSend: false)
            refreshError = ChatTexts.conversationGone
        } catch {
            refreshError = ChatTexts.message(for: error)
        }
    }

    /// Lädt ältere Nachrichten (beim Hochscrollen an den Anfang des Verlaufs).
    public func loadOlder() async {
        guard let repository, let conversation, hasOlderMessages, let oldest = messages.first else { return }
        if let olderTask {
            await olderTask.value
            return
        }
        let task = Task {
            self.isLoadingOlder = true
            do {
                let older = try await repository.messages(in: conversation.id, before: oldest.sentAt, limit: ChatRules.pageSize)
                self.hasOlderMessages = older.count >= ChatRules.pageSize
                self.merge(older)
                self.olderError = nil
            } catch is CancellationError {
                // Ansicht verlassen: beim nächsten Hochscrollen erneut.
            } catch {
                self.olderError = ChatTexts.olderFailed
            }
            self.isLoadingOlder = false
            self.olderTask = nil
        }
        olderTask = task
        await task.value
    }

    /// Hält den Chat aktuell, solange er sichtbar ist (`.task { await viewModel.observe() }`): Laden, Lesestand,
    /// Echtzeit-Ereignisse und als Rückfall regelmäßiges Abfragen. Endet, wenn die Aufgabe abgebrochen wird.
    public func observe() async {
        guard let repository else { return }
        observerCount += 1
        defer { observerCount -= 1 }
        let interval = pollInterval
        let sleep = sleep
        await loadIfNeeded()
        await markReadIfNeeded()
        // Ohne geladene Unterhaltung (z. B. offline): regelmäßig erneut versuchen, bis es klappt.
        while conversation == nil {
            if case .unavailable = state { return }
            do {
                try await sleep(interval)
            } catch {
                return
            }
            await loadIfNeeded()
        }
        guard let conversationID = conversation?.id else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                for await event in repository.conversationActivity(in: conversationID) {
                    switch event {
                    case .message, .messageUpdated:
                        await self?.refresh()
                    case .pinsChanged:
                        await self?.loadPins()
                    }
                }
            }
            group.addTask { [weak self] in
                while !Task.isCancelled {
                    do {
                        try await sleep(interval)
                    } catch {
                        return
                    }
                    await self?.refresh()
                }
            }
            await group.waitForAll()
        }
    }

    /// Meldet den Lesestand bis zur neuesten Nachricht – nur, solange der Chat sichtbar ist.
    private func markReadIfNeeded() async {
        guard isVisible, let repository, let conversation, let newest = messages.last else { return }
        if let lastReadMark, newest.sentAt <= lastReadMark { return }
        let previous = lastReadMark
        lastReadMark = newest.sentAt
        do {
            try await repository.markRead(conversation.id, through: newest.sentAt)
            list?.didMarkRead(conversation.id)
        } catch {
            // Beim nächsten Ereignis erneut versuchen.
            lastReadMark = previous
        }
    }

    /// Neue Stände aus der Chatliste übernehmen (z. B. Schreibrecht nach einer Blockierung oder neuer Gruppenname).
    func updateSummary(from conversations: [ConversationSummary]) {
        guard let current = conversation, let updated = conversations.first(where: { $0.id == current.id }) else { return }
        if updated != current {
            conversation = updated
        }
    }

    /// Passt dieses ViewModel zum Ziel (gleiche Unterhaltung, gleicher Freund bzw. gleiche Gruppe)?
    func matches(_ other: ChatTarget) -> Bool {
        if target == other { return true }
        switch other {
        case .conversation(let id, _, _):
            return conversation?.id == id
        case .direct(let profile):
            return kind == .direct && peer?.publicID == profile.publicID
        case .group(let id, _):
            return kind == .group && groupID == id
        }
    }

    // MARK: Senden

    /// Sendet den Text aus dem Eingabefeld. Die Nachricht erscheint sofort und wird bei Erfolg durch die gespeicherte
    /// ersetzt; bei einem Fehler bleibt sie mit „Erneut senden“ stehen.
    public func sendText() async {
        guard canSend else { return }
        guard let text = ChatRules.validText(draftText) else {
            if isDraftTooLong {
                notice = ChatNotice(text: ChatTexts.tooLong, isError: true)
            }
            return
        }
        if let editingMessage {
            await saveEdit(of: editingMessage, text: text)
            return
        }
        draftText = ""
        let message = PendingChatMessage(
            clientID: UUID(),
            kind: .text,
            text: text,
            localMedia: nil,
            mediaPath: nil,
            createdAt: now(),
            status: .sending,
            replyTo: takeReply()
        )
        pending.append(message)
        await deliver(message.clientID)
    }

    /// Sendet eine aufgenommene Sprachnachricht (AAC in .m4a). Erst hier wird hochgeladen – verworfene Aufnahmen
    /// verlassen das Gerät nie.
    public func sendVoice(_ data: Data, duration: Duration) async {
        guard canSend else { return }
        guard ChatRules.validVoiceMilliseconds(duration) != nil else {
            notice = ChatNotice(text: ChatTexts.voiceInvalidDuration, isError: true)
            return
        }
        guard !data.isEmpty, let conversation,
              data.count <= MediaRules.maximumBytes(for: .chat(conversationID: conversation.id))
        else {
            notice = ChatNotice(text: data.isEmpty ? ChatTexts.voiceRecordingFailed : ChatTexts.media(.tooLarge), isError: true)
            return
        }
        let message = PendingChatMessage(
            clientID: UUID(),
            kind: .voice,
            text: nil,
            localMedia: PendingChatMessage.LocalMedia(data: data, contentType: MediaRules.voiceContentType),
            mediaPath: nil,
            createdAt: now(),
            status: .uploading,
            replyTo: takeReply(),
            mediaDuration: duration
        )
        pending.append(message)
        await deliver(message.clientID)
    }

    /// Antwort-Vorschau für die nächste Nachricht übernehmen und die Antwort beenden.
    private func takeReply() -> ChatReplyPreview? {
        defer { replyingTo = nil }
        return replyingTo.map(ChatReplyPreview.init(replyingTo:))
    }

    /// Sendet ein Foto (bereits verkleinert, JPEG) oder ein GIF (unverändert, `image/gif`) aus der Mediathek.
    public func sendMedia(_ data: Data, contentType: String) async {
        guard canSend else { return }
        guard MediaRules.allowedContentTypes.contains(contentType) else {
            notice = ChatNotice(text: ChatTexts.media(.unsupportedType), isError: true)
            return
        }
        guard !data.isEmpty else {
            notice = ChatNotice(text: ChatTexts.mediaSelectionFailed, isError: true)
            return
        }
        guard let conversation, data.count <= MediaRules.maximumBytes(for: .chat(conversationID: conversation.id)) else {
            notice = ChatNotice(text: ChatTexts.media(.tooLarge), isError: true)
            return
        }
        let message = PendingChatMessage(
            clientID: UUID(),
            kind: contentType == "image/gif" ? .gif : .image,
            text: nil,
            localMedia: PendingChatMessage.LocalMedia(data: data, contentType: contentType),
            mediaPath: nil,
            createdAt: now(),
            status: .uploading,
            replyTo: takeReply()
        )
        pending.append(message)
        await deliver(message.clientID)
    }

    /// Meldet, dass ein ausgewähltes Bild nicht gelesen werden konnte.
    public func reportMediaSelectionFailed() {
        notice = ChatNotice(text: ChatTexts.mediaSelectionFailed, isError: true)
    }

    /// Sendet eine fehlgeschlagene Nachricht erneut – mit derselben `clientID`, damit der Server sie nur einmal anlegt.
    /// Ein bereits hochgeladenes Bild wird nicht noch einmal hochgeladen.
    public func retry(_ clientID: UUID) async {
        guard let index = pending.firstIndex(where: { $0.clientID == clientID }), pending[index].isFailed else { return }
        pending[index].status = pending[index].needsUpload ? .uploading : .sending
        await deliver(clientID)
    }

    /// Verwirft eine fehlgeschlagene Nachricht.
    public func discard(_ clientID: UUID) {
        guard let item = pending.first(where: { $0.clientID == clientID && $0.isFailed }) else { return }
        pending.removeAll { $0.clientID == clientID }
        // Schon hochgeladen, aber nie gesendet: Datei wieder entfernen (keine Reste im Speicher).
        if let path = item.mediaPath, let reference = MediaReference.chatMedia(path), let media {
            uploadedMedia[path] = nil
            Task { try? await media.delete(reference) }
        }
    }

    private func deliver(_ clientID: UUID) async {
        guard let repository, let conversationID = conversation?.id else {
            fail(clientID, message: ChatTexts.unavailable)
            return
        }
        guard let item = pending.first(where: { $0.clientID == clientID }) else { return }
        if item.needsUpload, let local = item.localMedia {
            guard let media else {
                fail(clientID, message: ChatTexts.mediaUnavailable)
                return
            }
            setStatus(.uploading, for: clientID)
            do {
                let reference = try await media.upload(local.data, contentType: local.contentType, to: .chat(conversationID: conversationID))
                uploadedMedia[reference.path] = local.data
                guard let index = pending.firstIndex(where: { $0.clientID == clientID }) else { return }
                pending[index].mediaPath = reference.path
            } catch {
                fail(clientID, message: ChatTexts.message(for: error))
                return
            }
        }
        setStatus(.sending, for: clientID)
        guard let draft = pending.first(where: { $0.clientID == clientID })?.draft else { return }
        do {
            let saved = try await repository.send(draft, to: conversationID)
            pending.removeAll { $0.clientID == clientID }
            merge([saved])
            list?.conversationDidChange()
        } catch let error as SocialError where error == .readOnly || error == .blocked {
            if let conversation { self.conversation = conversation.replacing(canSend: false) }
            fail(clientID, message: error.message)
        } catch {
            fail(clientID, message: ChatTexts.message(for: error))
        }
    }

    private func setStatus(_ status: PendingChatMessage.Status, for clientID: UUID) {
        guard let index = pending.firstIndex(where: { $0.clientID == clientID }) else { return }
        pending[index].status = status
    }

    private func fail(_ clientID: UUID, message: String) {
        setStatus(.failed(message), for: clientID)
    }

    // MARK: Nachrichten-Aktionen

    /// Löscht eine eigene Nachricht.
    public func delete(_ message: ChatMessage) async {
        guard message.isOwn, let repository, !busyMessageIDs.contains(message.id) else { return }
        busyMessageIDs.insert(message.id)
        defer { busyMessageIDs.remove(message.id) }
        do {
            try await repository.deleteMessage(message.id)
            messages.removeAll { $0.id == message.id }
            notice = ChatNotice(text: ChatTexts.messageDeleted, isError: false)
            list?.conversationDidChange()
        } catch {
            notice = ChatNotice(text: ChatTexts.message(for: error), isError: true)
        }
    }

    /// Meldet eine fremde Nachricht an das Pace-Team.
    public func report(_ message: ChatMessage, reason: ReportReason) async {
        guard !message.isOwn, !busyMessageIDs.contains(message.id) else { return }
        busyMessageIDs.insert(message.id)
        defer { busyMessageIDs.remove(message.id) }
        await submitReport(.message(id: message.id), reason: reason)
    }

    /// Meldet den Freund (Privatchat) bzw. die Gruppe (Gruppenchat).
    public func reportConversation(reason: ReportReason) async {
        let target: ReportTarget
        if kind == .group, let groupID {
            target = .group(id: groupID)
        } else if let peer {
            target = .user(publicID: peer.publicID)
        } else {
            return
        }
        isPerformingAction = true
        defer { isPerformingAction = false }
        await submitReport(target, reason: reason)
    }

    private func submitReport(_ target: ReportTarget, reason: ReportReason) async {
        guard let social else {
            notice = ChatNotice(text: SocialError.unavailable.message, isError: true)
            return
        }
        do {
            try await social.report(target, reason: reason, details: nil)
            notice = ChatNotice(text: ChatTexts.reported, isError: false)
        } catch {
            notice = ChatNotice(text: ChatTexts.message(for: error), isError: true)
        }
    }

    /// Blockiert eine Person (Gegenüber im Privatchat oder Absender in einer Gruppe). Danach sind keine neuen
    /// Nachrichten mehr möglich (Privatchat) bzw. ihre Nachrichten erscheinen eingeklappt (Gruppe).
    public func block(_ profile: SocialProfile) async {
        guard let social else {
            notice = ChatNotice(text: SocialError.unavailable.message, isError: true)
            return
        }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await social.block(profile.publicID)
            blockedUserIDs.insert(profile.publicID)
            if kind == .direct, let conversation, conversation.peer?.publicID == profile.publicID {
                self.conversation = conversation.replacing(canSend: false)
            }
            notice = ChatNotice(text: ChatTexts.blocked(profile.shownName), isError: false)
            list?.conversationDidChange()
        } catch {
            notice = ChatNotice(text: ChatTexts.message(for: error), isError: true)
        }
    }

    /// Zeigt eine eingeklappte Nachricht einer blockierten Person.
    public func reveal(_ messageID: UUID) {
        revealedMessageIDs.insert(messageID)
    }

    // MARK: Antworten, Bearbeiten, Favoriten, Pins

    /// Aktionen im Kontextmenü einer Nachricht – nur, was hier wirklich möglich ist.
    public func actions(for message: ChatMessage) -> [ChatMessageAction] {
        var actions: [ChatMessageAction] = []
        if canSend { actions.append(.reply) }
        if message.kind != .voice, let text = message.text, !text.isEmpty { actions.append(.copy) }
        if canSend, message.canEdit { actions.append(.edit) }
        if conversation != nil { actions.append(message.isFavorite ? .unfavorite : .favorite) }
        if canPin { actions.append(message.isPinned ? .unpin : .pin) }
        return actions
    }

    /// Anpinnen erlaubt (Gruppen: Owner, Privatchats: beide, solange sie schreiben dürfen; der Server prüft).
    public var canPin: Bool {
        canSend && conversation?.canPin == true
    }

    /// Antwort auf eine Nachricht beginnen (beendet ein laufendes Bearbeiten).
    public func startReply(to message: ChatMessage) {
        guard canSend else { return }
        if editingMessage != nil { cancelEditing() }
        replyingTo = message
    }

    public func cancelReply() {
        replyingTo = nil
    }

    /// Eigene Textnachricht bearbeiten: Ihr Text kommt ins Eingabefeld, der bisherige Entwurf wird aufbewahrt.
    public func startEditing(_ message: ChatMessage) {
        guard canSend, message.canEdit else { return }
        replyingTo = nil
        if editingMessage == nil {
            draftBeforeEditing = draftText
        }
        editingMessage = message
        draftText = message.text ?? ""
    }

    public func cancelEditing() {
        guard editingMessage != nil else { return }
        editingMessage = nil
        draftText = draftBeforeEditing ?? ""
        draftBeforeEditing = nil
    }

    private func saveEdit(of message: ChatMessage, text: String) async {
        guard let repository, !busyMessageIDs.contains(message.id) else { return }
        guard text != message.text else {
            cancelEditing()
            return
        }
        busyMessageIDs.insert(message.id)
        defer { busyMessageIDs.remove(message.id) }
        do {
            let saved = try await repository.editMessage(message.id, text: text)
            merge([saved])
            editingMessage = nil
            draftText = draftBeforeEditing ?? ""
            draftBeforeEditing = nil
            list?.conversationDidChange()
        } catch let error as SocialError where error == .notFound {
            // Inzwischen gelöscht: Bearbeiten beenden, Verlauf neu laden.
            editingMessage = nil
            draftText = draftBeforeEditing ?? ""
            draftBeforeEditing = nil
            notice = ChatNotice(text: ChatTexts.messageUnavailable, isError: true)
            await refresh()
        } catch {
            // Text bleibt im Eingabefeld, damit nichts verloren geht.
            notice = ChatNotice(text: ChatTexts.message(for: error), isError: true)
        }
    }

    /// Persönlicher Favorit (nur für dich sichtbar) – sofort angezeigt, bei einem Fehler zurückgenommen.
    public func toggleFavorite(_ message: ChatMessage) async {
        guard let repository, !busyMessageIDs.contains(message.id) else { return }
        let favorite = !message.isFavorite
        replaceMessage(message.id) { $0.withFavorite(favorite) }
        do {
            try await repository.setFavorite(message.id, isFavorite: favorite)
            notice = ChatNotice(text: favorite ? ChatTexts.favoriteAdded : ChatTexts.favoriteRemoved, isError: false)
            if case .loaded(var list) = favorites {
                list.removeAll { $0.id == message.id }
                if favorite, let current = messages.first(where: { $0.id == message.id }) {
                    list.append(current)
                    list.sort { $0.sentAt > $1.sentAt }
                }
                favorites = .loaded(list)
            }
        } catch {
            replaceMessage(message.id) { $0.withFavorite(!favorite) }
            notice = ChatNotice(text: ChatTexts.message(for: error), isError: true)
        }
    }

    /// Eigene Favoriten dieser Unterhaltung laden (Chat-Einstellungen).
    public func loadFavorites() async {
        guard let repository, let conversation else { return }
        if case .loaded = favorites {} else { favorites = .loading }
        do {
            favorites = .loaded(try await repository.favorites(conversationID: conversation.id))
        } catch is CancellationError {
            if case .loading = favorites { favorites = .idle }
        } catch {
            favorites = .failed(ChatTexts.message(for: error))
        }
    }

    /// Anpinnen bzw. lösen (für alle Teilnehmer).
    public func togglePin(_ message: ChatMessage) async {
        guard canPin, let repository, !busyMessageIDs.contains(message.id) else { return }
        let pin = !message.isPinned
        busyMessageIDs.insert(message.id)
        defer { busyMessageIDs.remove(message.id) }
        do {
            let updated = try await repository.setPinned(message.id, isPinned: pin)
            applyPins(updated)
            notice = ChatNotice(text: pin ? ChatTexts.pinned : ChatTexts.unpinned, isError: false)
        } catch let error as SocialError where error == .pinLimitReached {
            notice = ChatNotice(text: ChatTexts.pinLimitReached, isError: true)
        } catch {
            notice = ChatNotice(text: ChatTexts.message(for: error), isError: true)
        }
    }

    /// Angepinnte Nachrichten vom Server (beim Laden und nach einem Echtzeit-Hinweis). Ohne Unterstützung auf dem
    /// Server bleibt die Liste leer.
    func loadPins() async {
        guard let repository, let conversation else { return }
        do {
            applyPins(try await repository.pins(conversationID: conversation.id))
        } catch {
            // Pins sind ein Zusatz: Fehler hier stören den Chat nicht; beim nächsten Hinweis erneut.
        }
    }

    private func applyPins(_ updated: [ChatPin]) {
        pins = updated
        if pinIndex >= updated.count { pinIndex = 0 }
        let pinnedIDs = Set(updated.map(\.id))
        messages = messages.map { message in
            message.isPinned == pinnedIDs.contains(message.id) ? message : message.withPinned(pinnedIDs.contains(message.id))
        }
    }

    /// Pin, den der Hinweis oben zeigt.
    public var shownPin: ChatPin? {
        pins.indices.contains(pinIndex) ? pins[pinIndex] : pins.first
    }

    /// Antippen des Pin-Hinweises: zur Nachricht springen und danach den nächsten Pin zeigen.
    public func openShownPin() async {
        guard let pin = shownPin else { return }
        if pins.count > 1 {
            pinIndex = (pinIndex + 1) % pins.count
        }
        await jump(to: pin.message.id)
    }

    /// Springt zu einer Nachricht; ist sie noch nicht geladen, werden ältere Seiten nachgeladen (begrenzt). Gibt es
    /// sie nicht mehr, erscheint ein Hinweis.
    public func jump(to messageID: UUID) async {
        var pages = 0
        while !messages.contains(where: { $0.id == messageID }), hasOlderMessages, pages < Self.maximumJumpPages {
            let before = messages.count
            await loadOlder()
            pages += 1
            if messages.count == before { break }
        }
        guard messages.contains(where: { $0.id == messageID }) else {
            notice = ChatNotice(text: ChatTexts.messageUnavailable, isError: false)
            return
        }
        jumpRequest = ChatJumpRequest(messageID: messageID)
    }

    /// Die Ansicht hat zur Nachricht gescrollt und die Hervorhebung beendet.
    public func finishJump(_ request: ChatJumpRequest) {
        if jumpRequest == request {
            jumpRequest = nil
        }
    }

    /// So viele ältere Seiten werden für einen Sprung höchstens nachgeladen.
    static let maximumJumpPages = 10

    /// Name über der Antwort-Vorschau („Du“ bei eigenen Nachrichten).
    public func replyAuthor(of message: ChatMessage) -> String {
        message.isOwn ? ChatFormatting.ownPrefix : (message.sender?.shownName ?? ChatFormatting.deletedAccount)
    }

    /// Name im Verweis einer Antwort („Du“, wenn das Original von dir ist).
    public func replyAuthor(of preview: ChatReplyPreview) -> String {
        if let original = messages.first(where: { $0.id == preview.id }), original.isOwn {
            return ChatFormatting.ownPrefix
        }
        return preview.sender?.shownName ?? ChatFormatting.deletedAccount
    }

    private func replaceMessage(_ id: UUID, _ change: (ChatMessage) -> ChatMessage) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index] = change(messages[index])
    }
}

/// Aktion im Kontextmenü einer Nachricht.
public enum ChatMessageAction: Hashable, Sendable {
    case reply
    case copy
    case edit
    case favorite
    case unfavorite
    case pin
    case unpin
}

/// Auftrag an die Ansicht, zu einer Nachricht zu scrollen und sie kurz hervorzuheben (jede Anfrage einmalig).
public struct ChatJumpRequest: Equatable, Sendable {
    public let messageID: UUID
    public let id = UUID()

    public init(messageID: UUID) {
        self.messageID = messageID
    }
}

/// Favoritenliste einer Unterhaltung.
public enum ChatFavoritesState: Equatable, Sendable {
    case idle
    case loading
    case loaded([ChatMessage])
    case failed(String)
}

extension ChatReplyPreview {
    /// Vorschau einer geladenen Nachricht – für die eigene Antwort, bevor der Server sie liefert.
    init(replyingTo message: ChatMessage) {
        self.init(
            id: message.id,
            sender: message.sender,
            kind: message.kind,
            text: message.text.map { String($0.prefix(ChatRules.replyPreviewLength)) },
            mediaDuration: message.mediaDuration,
            isDeleted: false
        )
    }
}
