import Foundation
import PaceCore

// MARK: - Chat

/// Test-Double für `ChatRepository`: Unterhaltungen und Nachrichten im Speicher. Zugriffsregeln prüft der Server
/// (pgTAP-Tests); hier gibt es nur das Nötigste (z. B. `readOnly`, Fehler für alle Aufrufe).
public final class ChatRepositoryStub: ChatRepository, Sendable {
    public struct State: Sendable {
        public var conversations: [ConversationSummary] = []
        public var messages: [UUID: [ChatMessage]] = [:]
        /// Unterhaltung, die `openDirectConversation` je Person liefert.
        public var directConversations: [UUID: ConversationSummary] = [:]
        public var groupConversations: [UUID: ConversationSummary] = [:]
        public var error: SocialError?
        /// Fehler nur beim Senden.
        public var sendError: SocialError?
        public var readMarks: [(UUID, Date)] = []
        public var deleted: [UUID] = []
        public var calls: [String] = []
        public var me = SocialProfile(publicID: Fixtures.publicUserID, username: "niklas", displayName: "Niklas")
        public var now = Date(timeIntervalSince1970: 1_792_000_000)
        /// `false`: Echtzeit-Streams enden sofort (die App fällt auf regelmäßiges Abfragen zurück).
        public var realtimeAvailable = true
        /// Gesendete Entwürfe in Reihenfolge (auch Wiederholungen).
        public var sentDrafts: [(ChatMessageDraft, UUID)] = []
        /// Fehler nur beim Löschen.
        public var deleteError: SocialError?
        /// Profile, die bei geteilten Profilen zurückgegeben werden (sonst ein Platzhalter).
        public var sharedProfiles: [UUID: SocialProfile] = [:]
        /// Eigene Favoriten (Nachrichten-IDs).
        public var favoriteIDs: Set<UUID> = []
        /// Pins je Unterhaltung, zuletzt angepinnte zuerst.
        public var pins: [UUID: [ChatPin]] = [:]
        /// `false`: `setPinned` antwortet wie für Nicht-Owner im Gruppenchat (`notAllowed`).
        public var canPin = true
        /// Fehler nur bei Bearbeiten, Favoriten und Pins.
        public var actionError: SocialError?
    }

    public let state: Locked<State>
    public let gate = CallGate()
    private let messageContinuations = Locked<[UUID: [AsyncStream<Void>.Continuation]]>([:])
    private let activityContinuations = Locked<[UUID: [AsyncStream<ChatConversationEvent>.Continuation]]>([:])
    private let listContinuations = Locked<[AsyncStream<Void>.Continuation]>([])

    public init(configure: (inout State) -> Void = { _ in }) {
        var state = State()
        configure(&state)
        self.state = Locked(state)
    }

    private func check(_ name: String) throws {
        try state.withLock { state in
            state.calls.append(name)
            if let error = state.error { throw error }
        }
    }

    public func conversations() async throws -> [ConversationSummary] {
        try check("conversations")
        await gate.pass("conversations")
        return state.withLock { $0.conversations.sorted { $0.updatedAt > $1.updatedAt } }
    }

    public func openDirectConversation(with publicID: UUID) async throws -> ConversationSummary {
        try check("openDirectConversation")
        guard let conversation = state.withLock({ $0.directConversations[publicID] }) else { throw SocialError.notFound }
        return conversation
    }

    public func groupConversation(for groupID: UUID) async throws -> ConversationSummary {
        try check("groupConversation")
        guard let conversation = state.withLock({ $0.groupConversations[groupID] }) else { throw SocialError.notFound }
        return conversation
    }

    public func messages(in conversationID: UUID, before: Date?, limit: Int) async throws -> [ChatMessage] {
        try check("messages")
        await gate.pass("messages")
        return state.withLock { state in
            let all = (state.messages[conversationID] ?? []).sorted { $0.sentAt < $1.sentAt }
            let older = before.map { date in all.filter { $0.sentAt < date } } ?? all
            return Array(older.suffix(limit))
        }
    }

    public func send(_ draft: ChatMessageDraft, to conversationID: UUID) async throws -> ChatMessage {
        try check("send")
        await gate.pass("send")
        let message = try state.withLock { state -> ChatMessage in
            state.sentDrafts.append((draft, conversationID))
            if let error = state.sendError { throw error }
            if let existing = state.messages[conversationID]?.first(where: { $0.clientID == draft.clientID }) {
                return existing
            }
            state.now = state.now.addingTimeInterval(1)
            var reply: ChatReplyPreview?
            if let replyToID = draft.replyToID {
                guard let original = state.messages[conversationID]?.first(where: { $0.id == replyToID }) else {
                    throw SocialError.notFound
                }
                reply = ChatReplyPreview(
                    id: original.id,
                    sender: original.sender,
                    kind: original.kind,
                    text: original.text.map { String($0.prefix(ChatRules.replyPreviewLength)) },
                    mediaDuration: original.mediaDuration,
                    isDeleted: false
                )
            }
            let message = ChatMessage(
                id: UUID(),
                conversationID: conversationID,
                clientID: draft.clientID,
                sender: state.me,
                isOwn: true,
                kind: draft.kind,
                text: draft.text,
                media: .chatMedia(draft.mediaPath),
                sharedProfile: draft.sharedProfileID.map { id in
                    state.sharedProfiles[id] ?? SocialProfile(publicID: id, username: "geteilt", displayName: "Geteilt")
                },
                sentAt: state.now,
                replyPreview: reply,
                mediaDuration: draft.kind == .voice ? draft.mediaDuration : nil
            )
            state.messages[conversationID, default: []].append(message)
            return message
        }
        return message
    }

    public func markRead(_ conversationID: UUID, through: Date) async throws {
        try check("markRead")
        state.withLock { $0.readMarks.append((conversationID, through)) }
    }

    public func deleteMessage(_ messageID: UUID) async throws {
        try check("deleteMessage")
        try state.withLock { state in
            if let error = state.deleteError { throw error }
            state.deleted.append(messageID)
            for key in state.messages.keys {
                state.messages[key]?.removeAll { $0.id == messageID }
            }
        }
    }

    public func messageEvents(in conversationID: UUID) -> AsyncStream<Void> {
        AsyncStream { continuation in
            guard state.withLock({ $0.realtimeAvailable }) else {
                continuation.finish()
                return
            }
            messageContinuations.withLock { $0[conversationID, default: []].append(continuation) }
        }
    }

    // MARK: Nachrichtenaktionen

    private func checkAction(_ name: String) throws {
        try check(name)
        if let error = state.withLock({ $0.actionError }) { throw error }
    }

    public func editMessage(_ messageID: UUID, text: String) async throws -> ChatMessage {
        try checkAction("editMessage")
        guard let valid = ChatRules.validText(text) else { throw SocialError.invalidMessage }
        return try state.withLock { state in
            for key in state.messages.keys {
                guard let index = state.messages[key]?.firstIndex(where: { $0.id == messageID }) else { continue }
                let old = state.messages[key]![index]
                guard old.isOwn else { throw SocialError.notFound }
                guard old.kind == .text else { throw SocialError.invalidInput }
                state.now = state.now.addingTimeInterval(1)
                let edited = ChatMessage(
                    id: old.id, conversationID: old.conversationID, clientID: old.clientID, sender: old.sender, isOwn: old.isOwn,
                    kind: old.kind, text: valid, media: old.media, sharedProfile: old.sharedProfile, sentAt: old.sentAt,
                    replyPreview: old.replyPreview, editedAt: valid == old.text ? old.editedAt : state.now,
                    mediaDuration: old.mediaDuration, isFavorite: old.isFavorite, isPinned: old.isPinned
                )
                state.messages[key]![index] = edited
                return edited
            }
            throw SocialError.notFound
        }
    }

    public func setFavorite(_ messageID: UUID, isFavorite: Bool) async throws {
        try checkAction("setFavorite")
        try state.withLock { state in
            guard isFavorite else {
                state.favoriteIDs.remove(messageID)
                Self.update(&state, messageID) { $0.withFavorite(false) }
                return
            }
            guard state.messages.values.contains(where: { $0.contains { $0.id == messageID } }) else { throw SocialError.notFound }
            state.favoriteIDs.insert(messageID)
            Self.update(&state, messageID) { $0.withFavorite(true) }
        }
    }

    public func favorites(conversationID: UUID) async throws -> [ChatMessage] {
        try checkAction("favorites")
        return state.withLock { state in
            (state.messages[conversationID] ?? [])
                .filter { state.favoriteIDs.contains($0.id) }
                .sorted { $0.sentAt > $1.sentAt }
                .map { $0.withFavorite(true) }
        }
    }

    @discardableResult
    public func setPinned(_ messageID: UUID, isPinned: Bool) async throws -> [ChatPin] {
        try checkAction("setPinned")
        let (conversationID, pins) = try state.withLock { state -> (UUID, [ChatPin]) in
            guard let conversationID = state.messages.first(where: { $0.value.contains { $0.id == messageID } })?.key else {
                throw SocialError.notFound
            }
            guard state.canPin else { throw SocialError.notAllowed }
            var pins = state.pins[conversationID] ?? []
            if isPinned {
                if !pins.contains(where: { $0.message.id == messageID }) {
                    guard pins.count < ChatRules.maximumPinnedMessages else { throw SocialError.pinLimitReached }
                    let message = state.messages[conversationID]!.first { $0.id == messageID }!.withPinned(true)
                    state.now = state.now.addingTimeInterval(1)
                    pins.insert(ChatPin(message: message, pinnedBy: state.me, pinnedAt: state.now), at: 0)
                }
            } else {
                pins.removeAll { $0.message.id == messageID }
            }
            state.pins[conversationID] = pins
            Self.update(&state, messageID) { $0.withPinned(isPinned) }
            return (conversationID, pins)
        }
        sendActivity(.pinsChanged, in: conversationID)
        return pins
    }

    public func pins(conversationID: UUID) async throws -> [ChatPin] {
        try checkAction("pins")
        return state.withLock { $0.pins[conversationID] ?? [] }
    }

    public func conversationActivity(in conversationID: UUID) -> AsyncStream<ChatConversationEvent> {
        AsyncStream { continuation in
            guard state.withLock({ $0.realtimeAvailable }) else {
                continuation.finish()
                return
            }
            activityContinuations.withLock { $0[conversationID, default: []].append(continuation) }
        }
    }

    /// Simuliert einen Echtzeit-Hinweis mit Art (z. B. Bearbeitung durch einen zweiten Nutzer).
    public func sendActivity(_ event: ChatConversationEvent, in conversationID: UUID) {
        activityContinuations.withLock { $0[conversationID]?.forEach { $0.yield(event) } }
        if event == .message {
            messageContinuations.withLock { $0[conversationID]?.forEach { $0.yield() } }
        }
    }

    private static func update(_ state: inout State, _ messageID: UUID, _ transform: (ChatMessage) -> ChatMessage) {
        for key in state.messages.keys {
            if let index = state.messages[key]?.firstIndex(where: { $0.id == messageID }) {
                state.messages[key]![index] = transform(state.messages[key]![index])
            }
        }
    }

    public func conversationEvents() -> AsyncStream<Void> {
        AsyncStream { continuation in
            guard state.withLock({ $0.realtimeAvailable }) else {
                continuation.finish()
                return
            }
            listContinuations.withLock { $0.append(continuation) }
        }
    }

    /// Anzahl der Aufrufe einer Methode.
    public func callCount(_ name: String) -> Int {
        state.withLock { $0.calls.filter { $0 == name }.count }
    }

    /// Anzahl der offenen Echtzeit-Abos (Chatliste bzw. eine Unterhaltung).
    public func subscriberCount(conversationID: UUID? = nil) -> Int {
        if let conversationID {
            // Neue Nachrichten kommen je nach Aufrufer über `messageEvents` oder `conversationActivity`.
            return messageContinuations.withLock { $0[conversationID]?.count ?? 0 }
                + activityContinuations.withLock { $0[conversationID]?.count ?? 0 }
        }
        return listContinuations.withLock { $0.count }
    }

    /// Legt eine Nachricht auf dem Server ab, ohne ein Echtzeit-Ereignis zu senden (z. B. für den Polling-Rückfall).
    public func store(_ message: ChatMessage) {
        state.withLock { $0.messages[message.conversationID, default: []].append(message) }
    }

    /// Simuliert eine eingehende Nachricht (z. B. von einem zweiten Nutzer) inklusive Echtzeit-Ereignis.
    public func receive(_ message: ChatMessage) {
        state.withLock { $0.messages[message.conversationID, default: []].append(message) }
        messageContinuations.withLock { $0[message.conversationID]?.forEach { $0.yield() } }
        activityContinuations.withLock { $0[message.conversationID]?.forEach { $0.yield(.message) } }
        listContinuations.withLock { $0.forEach { $0.yield() } }
    }
}

// MARK: - Media

/// Test-Double für `MediaRepository`: speichert Dateien im Speicher.
public final class MediaRepositoryStub: MediaRepository, Sendable {
    public struct State: Sendable {
        public var files: [MediaReference: Data] = [:]
        public var uploads: [MediaUploadTarget] = []
        public var deleted: [MediaReference] = []
        public var error: MediaError?
    }

    public let state: Locked<State>

    public init(configure: (inout State) -> Void = { _ in }) {
        var state = State()
        configure(&state)
        self.state = Locked(state)
    }

    public func upload(_ data: Data, contentType: String, to target: MediaUploadTarget) async throws -> MediaReference {
        guard MediaRules.allowedContentTypes(for: target).contains(contentType) else { throw MediaError.unsupportedType }
        guard data.count <= MediaRules.maximumBytes(for: target) else { throw MediaError.tooLarge }
        return try state.withLock { state in
            if let error = state.error { throw error }
            state.uploads.append(target)
            let reference: MediaReference
            switch target {
            case .avatar: reference = MediaReference(bucket: .avatars, path: "\(Fixtures.publicUserID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg")
            case .groupImage(let id): reference = MediaReference(bucket: .groupImages, path: "\(id.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg")
            case .chat(let id):
                let suffix = MediaRules.isAudio(contentType) ? ".m4a" : ""
                reference = MediaReference(bucket: .chatMedia, path: "\(id.uuidString.lowercased())/\(UUID().uuidString.lowercased())\(suffix)")
            }
            state.files[reference] = data
            return reference
        }
    }

    public func data(for reference: MediaReference) async throws -> Data {
        try state.withLock { state in
            if let error = state.error { throw error }
            guard let data = state.files[reference] else { throw MediaError.notFound }
            return data
        }
    }

    public func delete(_ reference: MediaReference) async throws {
        try state.withLock { state in
            if let error = state.error { throw error }
            state.deleted.append(reference)
            state.files[reference] = nil
        }
    }
}

// MARK: - Steuerbares Warten

/// Ersatz für `Task.sleep` in Tests: Wartende laufen erst weiter, wenn der Test `tick()` aufruft. Damit lässt sich das
/// regelmäßige Aktualisieren (Polling-Rückfall) ohne echte Wartezeit prüfen.
public final class ManualTicker: Sendable {
    private struct State {
        var waiting: [UUID: CheckedContinuation<Void, any Error>] = [:]
        var cancelled: Set<UUID> = []
        var sleepCount = 0
    }

    private let state = Locked(State())

    public init() {}

    /// Wartet bis zum nächsten `tick()` (oder bis die Aufgabe abgebrochen wird).
    public func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let cancelled = state.withLock { state -> Bool in
                    if state.cancelled.remove(id) != nil { return true }
                    state.waiting[id] = continuation
                    state.sleepCount += 1
                    return false
                }
                if cancelled {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let continuation = state.withLock { state -> CheckedContinuation<Void, any Error>? in
                if let continuation = state.waiting.removeValue(forKey: id) { return continuation }
                state.cancelled.insert(id)
                return nil
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    /// Anzahl der gerade Wartenden.
    public var waitingCount: Int {
        state.withLock { $0.waiting.count }
    }

    /// Anzahl aller bisherigen Warteaufrufe.
    public var sleepCount: Int {
        state.withLock { $0.sleepCount }
    }

    /// Lässt alle Wartenden weiterlaufen.
    public func tick() {
        let continuations = state.withLock { state in
            let waiting = Array(state.waiting.values)
            state.waiting.removeAll()
            return waiting
        }
        continuations.forEach { $0.resume() }
    }
}

// MARK: - Beispieldaten für Chats

/// Beispiel-Unterhaltungen und -Nachrichten (nur Tests und Snapshots).
public enum ChatFixtures {
    public static let mia = SocialProfile(publicID: UUID(uuidString: "cccccccc-0000-4000-8000-000000000001")!, username: "mia", displayName: "Mia")
    public static let leon = SocialProfile(publicID: UUID(uuidString: "cccccccc-0000-4000-8000-000000000002")!, username: "leon", displayName: "Leon")
    public static let marie = SocialProfile(publicID: UUID(uuidString: "cccccccc-0000-4000-8000-000000000003")!, username: "marie", displayName: "Marie")
    public static let gotscha = SocialProfile(publicID: UUID(uuidString: "cccccccc-0000-4000-8000-000000000004")!, username: "gotscha", displayName: "Gotscha")

    public static func direct(
        id: UUID = UUID(),
        peer: SocialProfile = mia,
        last: ChatMessagePreview? = nil,
        unread: Int = 0,
        canSend: Bool = true,
        updatedAt: Date = Date(timeIntervalSince1970: 1_792_000_000),
        canPin: Bool = false
    ) -> ConversationSummary {
        ConversationSummary(
            id: id,
            kind: .direct,
            title: peer.displayName,
            peer: peer,
            groupID: nil,
            groupImagePath: nil,
            memberCount: 2,
            lastMessage: last,
            unreadCount: unread,
            canSend: canSend,
            updatedAt: updatedAt,
            canPin: canPin
        )
    }

    public static func group(
        id: UUID = UUID(),
        groupID: UUID = UUID(),
        title: String = "Smoking red",
        memberCount: Int = 12,
        last: ChatMessagePreview? = nil,
        unread: Int = 0,
        canSend: Bool = true,
        updatedAt: Date = Date(timeIntervalSince1970: 1_792_000_000),
        canPin: Bool = false
    ) -> ConversationSummary {
        ConversationSummary(
            id: id,
            kind: .group,
            title: title,
            peer: nil,
            groupID: groupID,
            groupImagePath: nil,
            memberCount: memberCount,
            lastMessage: last,
            unreadCount: unread,
            canSend: canSend,
            updatedAt: updatedAt,
            canPin: canPin
        )
    }

    public static func message(
        id: UUID = UUID(),
        in conversationID: UUID,
        from sender: SocialProfile?,
        isOwn: Bool = false,
        kind: ChatMessageKind = .text,
        text: String? = nil,
        mediaPath: String? = nil,
        sharedProfile: SocialProfile? = nil,
        clientID: UUID? = nil,
        at sentAt: Date,
        replyPreview: ChatReplyPreview? = nil,
        editedAt: Date? = nil,
        mediaDuration: Duration? = nil,
        isFavorite: Bool = false,
        isPinned: Bool = false
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            conversationID: conversationID,
            clientID: clientID,
            sender: sender,
            isOwn: isOwn,
            kind: kind,
            text: text,
            media: .chatMedia(mediaPath),
            sharedProfile: sharedProfile,
            sentAt: sentAt,
            replyPreview: replyPreview,
            editedAt: editedAt,
            mediaDuration: mediaDuration,
            isFavorite: isFavorite,
            isPinned: isPinned
        )
    }
}
