import Foundation
import PaceCore
import PostgREST
import Storage

/// Privat- und Gruppenchats per RPC (Migrationen 20261019100200 und 20261023100100: Antworten, Bearbeiten, Favoriten,
/// Pins, Sprachnachrichten). Zugriff, Validierung, Idempotenz und Rate Limits prüft der Server; Fehler kommen als
/// `SocialError` (z. B. `.readOnly`, `.invalidMessage`, `.blocked`, `.notAllowed`, `.pinLimitReached`).
///
/// Echtzeit: `messageEvents`, `conversationActivity` und `conversationEvents` melden Hinweise des Servers über private
/// Realtime-Kanäle. Ist Realtime nicht erreichbar, enden die Streams sofort und die App aktualisiert regelmäßig.
struct SupabaseChatRepository: ChatRepository {
    let client: PostgrestClient
    let storage: SupabaseStorageClient
    let realtime: RealtimeEvents
    let ownPublicID: OwnPublicID

    func conversations() async throws -> [ConversationSummary] {
        let rows: [ConversationRow] = try await mapped {
            try await client.rpc("chat_conversations").execute().value
        }
        return rows.map(\.summary)
    }

    func openDirectConversation(with publicID: UUID) async throws -> ConversationSummary {
        let row: ConversationRow = try await mapped {
            try await client.rpc("chat_open_direct", params: ["p_public_id": publicID]).execute().value
        }
        return row.summary
    }

    func groupConversation(for groupID: UUID) async throws -> ConversationSummary {
        let row: ConversationRow = try await mapped {
            try await client.rpc("chat_group_conversation", params: ["p_group_id": groupID]).execute().value
        }
        return row.summary
    }

    func messages(in conversationID: UUID, before: Date?, limit: Int) async throws -> [ChatMessage] {
        let params = MessagesParams(
            conversationID: conversationID,
            before: before.map(BackendTimestamp.string(from:)),
            limit: min(max(limit, 1), 100)
        )
        let rows: [ChatMessageRow] = try await mapped {
            try await client.rpc("chat_messages", params: params).execute().value
        }
        return rows.map(\.message)
    }

    func send(_ draft: ChatMessageDraft, to conversationID: UUID) async throws -> ChatMessage {
        var text: String?
        if draft.kind == .text {
            // Leere oder zu lange Texte gar nicht erst senden (gleiche Regel wie auf dem Server).
            guard let valid = ChatRules.validText(draft.text ?? "") else { throw SocialError.invalidMessage }
            text = valid
        }
        var durationMilliseconds: Int?
        if draft.kind == .voice {
            // Sprachnachrichten brauchen Datei und Dauer (1 ms bis 5 min), wie auf dem Server.
            guard draft.mediaPath != nil, let duration = draft.mediaDuration,
                  let milliseconds = ChatRules.validVoiceMilliseconds(duration) else {
                throw SocialError.invalidInput
            }
            durationMilliseconds = milliseconds
        }
        // Nur gesetzte Werte werden gesendet: Ohne Antwort und Dauer passt der Aufruf auch zu Servern vor Migration
        // 20261023100100.
        let params = SendParams(
            conversationID: conversationID,
            clientID: draft.clientID,
            kind: draft.kind.rawValue,
            body: text,
            mediaPath: draft.mediaPath,
            sharedProfileID: draft.sharedProfileID,
            replyToID: draft.replyToID,
            mediaDurationMilliseconds: durationMilliseconds
        )
        let row: ChatMessageRow = try await mapped {
            try await client.rpc("chat_send", params: params).execute().value
        }
        return row.message
    }

    func markRead(_ conversationID: UUID, through: Date) async throws {
        try await mapped {
            try await client.rpc(
                "chat_mark_read",
                params: MarkReadParams(conversationID: conversationID, through: BackendTimestamp.string(from: through))
            ).execute()
        }
    }

    /// Entfernt danach auch die Datei eines Bildes bzw. GIFs aus Storage. Scheitert nur das, bleibt die Nachricht
    /// gelöscht; die Datei entfernt spätestens das Löschen des Kontos (`AccountRepository.ownMedia`).
    func deleteMessage(_ messageID: UUID) async throws {
        let row: DeletedMessageRow = try await mapped {
            try await client.rpc("chat_delete_message", params: ["p_message_id": messageID]).execute().value
        }
        if let mediaPath = row.mediaPath {
            _ = try? await storage.from(MediaBucket.chatMedia.rawValue).remove(paths: [mediaPath])
        }
    }

    func messageEvents(in conversationID: UUID) -> AsyncStream<Void> {
        realtime.stream(topic: Self.chatTopic(conversationID), event: ChatConversationEvent.message.rawValue)
    }

    // MARK: Nachrichtenaktionen

    func editMessage(_ messageID: UUID, text: String) async throws -> ChatMessage {
        guard let valid = ChatRules.validText(text) else { throw SocialError.invalidMessage }
        let row: ChatMessageRow = try await mapped {
            try await client.rpc("chat_edit_message", params: EditParams(messageID: messageID, text: valid)).execute().value
        }
        return row.message
    }

    func setFavorite(_ messageID: UUID, isFavorite: Bool) async throws {
        try await mapped {
            try await client.rpc("chat_set_favorite", params: FavoriteParams(messageID: messageID, favorite: isFavorite)).execute()
        }
    }

    func favorites(conversationID: UUID) async throws -> [ChatMessage] {
        let rows: [ChatMessageRow] = try await mapped {
            try await client.rpc("chat_favorites", params: ["p_conversation_id": conversationID]).execute().value
        }
        return rows.map(\.message)
    }

    @discardableResult
    func setPinned(_ messageID: UUID, isPinned: Bool) async throws -> [ChatPin] {
        let rows: [ChatPinRow] = try await mapped {
            try await client.rpc("chat_set_pinned", params: PinParams(messageID: messageID, pinned: isPinned)).execute().value
        }
        return rows.map(\.pin)
    }

    func pins(conversationID: UUID) async throws -> [ChatPin] {
        let rows: [ChatPinRow] = try await mapped {
            try await client.rpc("chat_pins", params: ["p_conversation_id": conversationID]).execute().value
        }
        return rows.map(\.pin)
    }

    /// Ein Kanal je Unterhaltung für alle drei Hinweise; unbekannte Ereignisse werden übergangen.
    func conversationActivity(in conversationID: UUID) -> AsyncStream<ChatConversationEvent> {
        let events = realtime.stream(topic: Self.chatTopic(conversationID), events: ChatConversationEvent.allCases.map(\.rawValue))
        return AsyncStream { continuation in
            let task = Task {
                for await name in events {
                    if let event = ChatConversationEvent(rawValue: name) {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func chatTopic(_ conversationID: UUID) -> String {
        "chat:\(conversationID.uuidString.lowercased())"
    }

    func conversationEvents() -> AsyncStream<Void> {
        let ownPublicID = ownPublicID
        return realtime.stream(event: "conversation") {
            let publicID = try await ownPublicID.value()
            return "user:\(publicID.uuidString.lowercased())"
        }
    }

    @discardableResult
    private func mapped<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            if BackendFailure.isCancellation(error) { throw CancellationError() }
            throw BackendErrorMapping.socialError(error)
        }
    }
}

// MARK: - Parameter

private struct MessagesParams: Encodable {
    let conversationID: UUID
    let before: String?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case conversationID = "p_conversation_id"
        case before = "p_before"
        case limit = "p_limit"
    }
}

private struct SendParams: Encodable {
    let conversationID: UUID
    let clientID: UUID
    let kind: String
    let body: String?
    let mediaPath: String?
    let sharedProfileID: UUID?
    let replyToID: UUID?
    let mediaDurationMilliseconds: Int?

    enum CodingKeys: String, CodingKey {
        case conversationID = "p_conversation_id"
        case clientID = "p_client_id"
        case kind = "p_kind"
        case body = "p_body"
        case mediaPath = "p_media_path"
        case sharedProfileID = "p_shared_profile_id"
        case replyToID = "p_reply_to_id"
        case mediaDurationMilliseconds = "p_media_duration_ms"
    }
}

private struct EditParams: Encodable {
    let messageID: UUID
    let text: String

    enum CodingKeys: String, CodingKey {
        case messageID = "p_message_id"
        case text = "p_text"
    }
}

private struct FavoriteParams: Encodable {
    let messageID: UUID
    let favorite: Bool

    enum CodingKeys: String, CodingKey {
        case messageID = "p_message_id"
        case favorite = "p_favorite"
    }
}

private struct PinParams: Encodable {
    let messageID: UUID
    let pinned: Bool

    enum CodingKeys: String, CodingKey {
        case messageID = "p_message_id"
        case pinned = "p_pinned"
    }
}

private struct MarkReadParams: Encodable {
    let conversationID: UUID
    let through: String

    enum CodingKeys: String, CodingKey {
        case conversationID = "p_conversation_id"
        case through = "p_through"
    }
}
