import Foundation
import PaceCore

// Antworten der Chat-RPCs (Migrationen 20261019100200, 20261023100100) und der Datenschutz-RPCs. Zeitstempel kommen als
// `timestamptz`-String mit Mikrosekunden.

/// Eine Unterhaltung (`chat_conversations`, `chat_open_direct`, `chat_group_conversation`).
struct ConversationRow: Decodable {
    let id: UUID
    let kind: ConversationKind
    let title: String
    let peer: SocialProfileRow?
    let groupID: UUID?
    let groupImagePath: String?
    let memberCount: Int
    let lastMessage: ChatPreviewRow?
    let unreadCount: Int
    let canSend: Bool
    let updatedAt: Date
    let canPin: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case peer
        case groupID = "group_id"
        case groupImagePath = "group_image_path"
        case memberCount = "member_count"
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
        case canSend = "can_send"
        case updatedAt = "updated_at"
        case canPin = "can_pin"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try ConversationKind(rawValue: container.decode(String.self, forKey: .kind)) ?? .direct
        // Ohne Titel (Konto des Gegenübers gelöscht) bleibt er leer; die App zeigt dann einen eigenen Hinweis.
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        peer = try container.decodeIfPresent(SocialProfileRow.self, forKey: .peer)
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        groupImagePath = try container.decodeIfPresent(String.self, forKey: .groupImagePath)
        memberCount = try container.decode(Int.self, forKey: .memberCount)
        lastMessage = try container.decodeIfPresent(ChatPreviewRow.self, forKey: .lastMessage)
        unreadCount = try container.decode(Int.self, forKey: .unreadCount)
        canSend = try container.decode(Bool.self, forKey: .canSend)
        updatedAt = try container.decodeTimestamp(forKey: .updatedAt)
        // Vor Migration 20261023100100 gibt es keine Pins.
        canPin = try container.decodeIfPresent(Bool.self, forKey: .canPin) ?? false
    }

    var summary: ConversationSummary {
        ConversationSummary(
            id: id,
            kind: kind,
            title: title,
            peer: peer?.profile,
            groupID: groupID,
            groupImagePath: groupImagePath,
            memberCount: memberCount,
            lastMessage: lastMessage?.preview,
            unreadCount: unreadCount,
            canSend: canSend,
            updatedAt: updatedAt,
            canPin: canPin
        )
    }
}

/// Letzte Nachricht einer Unterhaltung.
struct ChatPreviewRow: Decodable {
    let kind: ChatMessageKind
    let text: String?
    let senderName: String?
    let isOwn: Bool
    let sentAt: Date
    let senderNickname: String?
    let mediaDurationMilliseconds: Int?

    enum CodingKeys: String, CodingKey {
        case kind
        case text
        case senderName = "sender_name"
        case isOwn = "is_own"
        case sentAt = "sent_at"
        case senderNickname = "sender_nickname"
        case mediaDurationMilliseconds = "media_duration_ms"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try ChatMessageKind(rawValue: container.decode(String.self, forKey: .kind)) ?? .text
        text = try container.decodeIfPresent(String.self, forKey: .text)
        senderName = try container.decodeIfPresent(String.self, forKey: .senderName)
        isOwn = try container.decode(Bool.self, forKey: .isOwn)
        sentAt = try container.decodeTimestamp(forKey: .sentAt)
        senderNickname = try container.decodeIfPresent(String.self, forKey: .senderNickname)
        mediaDurationMilliseconds = try container.decodeIfPresent(Int.self, forKey: .mediaDurationMilliseconds)
    }

    var preview: ChatMessagePreview {
        ChatMessagePreview(
            kind: kind,
            text: text,
            senderName: senderName,
            isOwn: isOwn,
            sentAt: sentAt,
            senderNickname: senderNickname,
            mediaDuration: mediaDurationMilliseconds.map { .milliseconds($0) }
        )
    }
}

/// Eine Nachricht (`chat_messages`, `chat_send`).
struct ChatMessageRow: Decodable {
    let id: UUID
    let conversationID: UUID
    let clientID: UUID?
    let sender: SocialProfileRow?
    let isOwn: Bool
    let kind: ChatMessageKind
    let body: String?
    let mediaPath: String?
    let sharedProfile: SocialProfileRow?
    let createdAt: Date
    let mediaDurationMilliseconds: Int?
    let replyTo: ChatReplyRow?
    let editedAt: Date?
    let isFavorite: Bool
    let isPinned: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversation_id"
        case clientID = "client_id"
        case sender
        case isOwn = "is_own"
        case kind
        case body
        case mediaPath = "media_path"
        case sharedProfile = "shared_profile"
        case createdAt = "created_at"
        case mediaDurationMilliseconds = "media_duration_ms"
        case replyTo = "reply_to"
        case editedAt = "edited_at"
        case isFavorite = "is_favorite"
        case isPinned = "is_pinned"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        conversationID = try container.decode(UUID.self, forKey: .conversationID)
        clientID = try container.decodeIfPresent(UUID.self, forKey: .clientID)
        sender = try container.decodeIfPresent(SocialProfileRow.self, forKey: .sender)
        isOwn = try container.decode(Bool.self, forKey: .isOwn)
        kind = try ChatMessageKind(rawValue: container.decode(String.self, forKey: .kind)) ?? .text
        body = try container.decodeIfPresent(String.self, forKey: .body)
        mediaPath = try container.decodeIfPresent(String.self, forKey: .mediaPath)
        sharedProfile = try container.decodeIfPresent(SocialProfileRow.self, forKey: .sharedProfile)
        createdAt = try container.decodeTimestamp(forKey: .createdAt)
        // Die folgenden Felder fehlen bei Servern ohne Migration 20261023100100.
        mediaDurationMilliseconds = try container.decodeIfPresent(Int.self, forKey: .mediaDurationMilliseconds)
        replyTo = try container.decodeIfPresent(ChatReplyRow.self, forKey: .replyTo)
        editedAt = try container.decodeTimestampIfPresent(forKey: .editedAt)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    var message: ChatMessage {
        ChatMessage(
            id: id,
            conversationID: conversationID,
            clientID: clientID,
            sender: sender?.profile,
            isOwn: isOwn,
            kind: kind,
            text: body,
            media: .chatMedia(mediaPath),
            sharedProfile: sharedProfile?.profile,
            sentAt: createdAt,
            replyPreview: replyTo?.preview,
            editedAt: editedAt,
            mediaDuration: mediaDurationMilliseconds.map { .milliseconds($0) },
            isFavorite: isFavorite,
            isPinned: isPinned
        )
    }
}

/// Vorschau der Nachricht, auf die geantwortet wird (`reply_to` in `chat_message_json`).
struct ChatReplyRow: Decodable {
    let id: UUID
    let sender: SocialProfileRow?
    let kind: ChatMessageKind
    let text: String?
    let mediaDurationMilliseconds: Int?
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case sender
        case kind
        case text
        case mediaDurationMilliseconds = "media_duration_ms"
        case isDeleted = "is_deleted"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sender = try container.decodeIfPresent(SocialProfileRow.self, forKey: .sender)
        kind = try ChatMessageKind(rawValue: container.decode(String.self, forKey: .kind)) ?? .text
        text = try container.decodeIfPresent(String.self, forKey: .text)
        mediaDurationMilliseconds = try container.decodeIfPresent(Int.self, forKey: .mediaDurationMilliseconds)
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }

    var preview: ChatReplyPreview {
        ChatReplyPreview(
            id: id,
            sender: sender?.profile,
            kind: kind,
            text: text,
            mediaDuration: mediaDurationMilliseconds.map { .milliseconds($0) },
            isDeleted: isDeleted
        )
    }
}

/// Ein Pin (`chat_pins`, `chat_set_pinned`).
struct ChatPinRow: Decodable {
    let message: ChatMessageRow
    let pinnedBy: SocialProfileRow?
    let pinnedAt: Date

    enum CodingKeys: String, CodingKey {
        case message
        case pinnedBy = "pinned_by"
        case pinnedAt = "pinned_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(ChatMessageRow.self, forKey: .message)
        pinnedBy = try container.decodeIfPresent(SocialProfileRow.self, forKey: .pinnedBy)
        pinnedAt = try container.decodeTimestamp(forKey: .pinnedAt)
    }

    var pin: ChatPin {
        ChatPin(message: message.message, pinnedBy: pinnedBy?.profile, pinnedAt: pinnedAt)
    }
}

/// Antwort von `chat_delete_message`: Datei der gelöschten Nachricht, die die App aus Storage entfernt.
struct DeletedMessageRow: Decodable {
    let mediaPath: String?

    enum CodingKeys: String, CodingKey {
        case mediaPath = "media_path"
    }
}

/// Eintrag von `account_own_media`.
struct MediaReferenceRow: Decodable {
    let bucket: String
    let path: String

    /// `nil` für unbekannte Buckets (neuere Server).
    var reference: MediaReference? {
        MediaBucket(rawValue: bucket).map { MediaReference(bucket: $0, path: path) }
    }
}
