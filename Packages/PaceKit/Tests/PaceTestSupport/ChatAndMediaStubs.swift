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
    }

    public let state: Locked<State>
    public let gate = CallGate()
    private let messageContinuations = Locked<[UUID: [AsyncStream<Void>.Continuation]]>([:])
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
            if let error = state.sendError { throw error }
            if let existing = state.messages[conversationID]?.first(where: { $0.clientID == draft.clientID }) {
                return existing
            }
            state.now = state.now.addingTimeInterval(1)
            let message = ChatMessage(
                id: UUID(),
                conversationID: conversationID,
                clientID: draft.clientID,
                sender: state.me,
                isOwn: true,
                kind: draft.kind,
                text: draft.text,
                media: .chatMedia(draft.mediaPath),
                sharedProfile: draft.sharedProfileID.map { SocialProfile(publicID: $0, username: "geteilt", displayName: "Geteilt") },
                sentAt: state.now
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
        state.withLock { state in
            state.deleted.append(messageID)
            for key in state.messages.keys {
                state.messages[key]?.removeAll { $0.id == messageID }
            }
        }
    }

    public func messageEvents(in conversationID: UUID) -> AsyncStream<Void> {
        AsyncStream { continuation in
            messageContinuations.withLock { $0[conversationID, default: []].append(continuation) }
        }
    }

    public func conversationEvents() -> AsyncStream<Void> {
        AsyncStream { continuation in
            listContinuations.withLock { $0.append(continuation) }
        }
    }

    /// Simuliert eine eingehende Nachricht (z. B. von einem zweiten Nutzer) inklusive Echtzeit-Ereignis.
    public func receive(_ message: ChatMessage) {
        state.withLock { $0.messages[message.conversationID, default: []].append(message) }
        messageContinuations.withLock { $0[message.conversationID]?.forEach { $0.yield() } }
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
        guard MediaRules.allowedContentTypes.contains(contentType) else { throw MediaError.unsupportedType }
        guard data.count <= MediaRules.maximumBytes(for: target) else { throw MediaError.tooLarge }
        return try state.withLock { state in
            if let error = state.error { throw error }
            state.uploads.append(target)
            let reference: MediaReference
            switch target {
            case .avatar: reference = MediaReference(bucket: .avatars, path: "\(Fixtures.publicUserID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg")
            case .groupImage(let id): reference = MediaReference(bucket: .groupImages, path: "\(id.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg")
            case .chat(let id): reference = MediaReference(bucket: .chatMedia, path: "\(id.uuidString.lowercased())/\(UUID().uuidString.lowercased())")
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

// MARK: - Account

/// Test-Double für `AccountRepository`.
public final class AccountRepositoryStub: AccountRepository, Sendable {
    public struct State: Sendable {
        public var exportJSON = Data(#"{"profile":{"username":"niklas"}}"#.utf8)
        public var media: [MediaReference] = []
        public var error: AccountError?
        public var deleteCalls = 0
        public var feedback: [(FeedbackKind, String, String)] = []
    }

    public let state: Locked<State>

    public init(configure: (inout State) -> Void = { _ in }) {
        var state = State()
        configure(&state)
        self.state = Locked(state)
    }

    public func exportData() async throws -> Data {
        try state.withLock { state in
            if let error = state.error { throw error }
            return state.exportJSON
        }
    }

    public func ownMedia() async throws -> [MediaReference] {
        try state.withLock { state in
            if let error = state.error { throw error }
            return state.media
        }
    }

    public func deleteAccount() async throws {
        try state.withLock { state in
            if let error = state.error { throw error }
            state.deleteCalls += 1
        }
    }

    public func submitFeedback(kind: FeedbackKind, message: String, appVersion: String) async throws {
        try state.withLock { state in
            if let error = state.error { throw error }
            state.feedback.append((kind, message, appVersion))
        }
    }
}

// MARK: - Mitteilungen

/// Test-Double für lokale Mitteilungen.
public final class NotificationSchedulerStub: LocalNotificationScheduling, Sendable {
    public struct State: Sendable {
        public var authorization: NotificationAuthorization = .notDetermined
        public var grantsOnRequest = true
        public var scheduled: [(hour: Int, minute: Int, skipToday: Bool)] = []
        public var cancelCalls = 0
    }

    public let state: Locked<State>

    public init(configure: (inout State) -> Void = { _ in }) {
        var state = State()
        configure(&state)
        self.state = Locked(state)
    }

    public func authorization() async -> NotificationAuthorization {
        state.withLock { $0.authorization }
    }

    public func requestAuthorization() async -> Bool {
        state.withLock { state in
            state.authorization = state.grantsOnRequest ? .authorized : .denied
            return state.grantsOnRequest
        }
    }

    public func scheduleStreakReminders(hour: Int, minute: Int, skipToday: Bool, title: String, body: String) async {
        state.withLock { $0.scheduled.append((hour, minute, skipToday)) }
    }

    public func cancelStreakReminders() async {
        state.withLock { $0.cancelCalls += 1 }
    }
}
