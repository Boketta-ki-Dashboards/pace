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
    @ObservationIgnored private var isVisible = false
    /// Gerade hochgeladene Bilder (Pfad → Daten), damit sie nicht noch einmal geladen werden müssen.
    @ObservationIgnored private var uploadedMedia: [String: Data] = [:]

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
        if let conversation { return conversation.title }
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
        return ChatTexts.readOnly(kind: kind, peerName: peer?.displayName, blockedByMe: blockedByMe)
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
        isVisible = true
        defer { isVisible = false }
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
                for await _ in repository.messageEvents(in: conversationID) {
                    await self?.refresh()
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
        draftText = ""
        let message = PendingChatMessage(
            clientID: UUID(),
            kind: .text,
            text: text,
            localMedia: nil,
            mediaPath: nil,
            createdAt: now(),
            status: .sending
        )
        pending.append(message)
        await deliver(message.clientID)
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
            status: .uploading
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
        pending.removeAll { $0.clientID == clientID && $0.isFailed }
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
            notice = ChatNotice(text: ChatTexts.blocked(profile.displayName), isError: false)
            list?.conversationDidChange()
        } catch {
            notice = ChatNotice(text: ChatTexts.message(for: error), isError: true)
        }
    }

    /// Zeigt eine eingeklappte Nachricht einer blockierten Person.
    public func reveal(_ messageID: UUID) {
        revealedMessageIDs.insert(messageID)
    }
}
