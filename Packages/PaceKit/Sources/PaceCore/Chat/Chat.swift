import Foundation

/// Art einer Unterhaltung.
public enum ConversationKind: String, Codable, Sendable {
    /// Zwischen zwei Freunden.
    case direct
    /// Gruppenchat einer Pace-Gruppe (Teilnehmer = aktuelle Mitglieder).
    case group
}

/// Art einer Nachricht.
public enum ChatMessageKind: String, Codable, Sendable {
    case text
    /// Foto (Bucket `chat-media`).
    case image
    /// Animiertes GIF (Bucket `chat-media`, Inhaltstyp `image/gif`).
    case gif
    /// Innerhalb von Pace geteiltes Profil.
    case profile
}

/// Kurzfassung der letzten Nachricht für die Chatliste.
public struct ChatMessagePreview: Equatable, Sendable {
    public let kind: ChatMessageKind
    /// Text der Nachricht (bei Bildern/GIFs/Profilen `nil`).
    public let text: String?
    /// Anzeigename des Absenders; `nil` bei eigenen Nachrichten.
    public let senderName: String?
    public let isOwn: Bool
    public let sentAt: Date

    public init(kind: ChatMessageKind, text: String?, senderName: String?, isOwn: Bool, sentAt: Date) {
        self.kind = kind
        self.text = text
        self.senderName = senderName
        self.isOwn = isOwn
        self.sentAt = sentAt
    }
}

/// Eine Unterhaltung in der Chatliste.
public struct ConversationSummary: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let kind: ConversationKind
    /// Anzeigename des Freundes bzw. Gruppenname.
    public let title: String
    /// Gesprächspartner bei direkten Chats.
    public let peer: SocialProfile?
    /// Gruppe bei Gruppenchats.
    public let groupID: UUID?
    /// Gruppenbild (Bucket `group-images`) bei Gruppenchats.
    public let groupImagePath: String?
    public let memberCount: Int
    public let lastMessage: ChatMessagePreview?
    public let unreadCount: Int
    /// `false`, wenn nicht mehr geschrieben werden kann (z. B. nach Ende der Freundschaft oder einer Blockierung).
    public let canSend: Bool
    /// Zeitpunkt der letzten Aktivität (letzte Nachricht oder Erstellung) – Sortierung der Liste.
    public let updatedAt: Date

    public init(
        id: UUID,
        kind: ConversationKind,
        title: String,
        peer: SocialProfile?,
        groupID: UUID?,
        groupImagePath: String?,
        memberCount: Int,
        lastMessage: ChatMessagePreview?,
        unreadCount: Int,
        canSend: Bool,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.peer = peer
        self.groupID = groupID
        self.groupImagePath = groupImagePath
        self.memberCount = memberCount
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.canSend = canSend
        self.updatedAt = updatedAt
    }

    /// Bild für die Liste: Profilbild des Freundes bzw. Gruppenbild.
    public var image: MediaReference? {
        switch kind {
        case .direct: peer?.avatar
        case .group: .groupImage(groupImagePath)
        }
    }
}

/// Eine Nachricht im Verlauf.
public struct ChatMessage: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let conversationID: UUID
    /// Vom Gerät vergebene ID zum gefahrlosen Wiederholen (keine doppelten Nachrichten).
    public let clientID: UUID?
    /// Absender; `nil`, wenn das Konto gelöscht wurde.
    public let sender: SocialProfile?
    public let isOwn: Bool
    public let kind: ChatMessageKind
    public let text: String?
    /// Bild oder GIF.
    public let media: MediaReference?
    /// Geteiltes Profil (bei `kind == .profile`).
    public let sharedProfile: SocialProfile?
    public let sentAt: Date

    public init(
        id: UUID,
        conversationID: UUID,
        clientID: UUID?,
        sender: SocialProfile?,
        isOwn: Bool,
        kind: ChatMessageKind,
        text: String?,
        media: MediaReference?,
        sharedProfile: SocialProfile?,
        sentAt: Date
    ) {
        self.id = id
        self.conversationID = conversationID
        self.clientID = clientID
        self.sender = sender
        self.isOwn = isOwn
        self.kind = kind
        self.text = text
        self.media = media
        self.sharedProfile = sharedProfile
        self.sentAt = sentAt
    }
}

/// Neue Nachricht. `clientID` bleibt bei Wiederholungen gleich – der Server legt sie nur einmal an.
public struct ChatMessageDraft: Equatable, Sendable {
    public let clientID: UUID
    public let kind: ChatMessageKind
    public let text: String?
    /// Vorher hochgeladenes Bild/GIF (Bucket `chat-media`).
    public let mediaPath: String?
    /// Geteiltes Profil.
    public let sharedProfileID: UUID?

    public init(clientID: UUID = UUID(), kind: ChatMessageKind, text: String? = nil, mediaPath: String? = nil, sharedProfileID: UUID? = nil) {
        self.clientID = clientID
        self.kind = kind
        self.text = text
        self.mediaPath = mediaPath
        self.sharedProfileID = sharedProfileID
    }

    public static func text(_ text: String, clientID: UUID = UUID()) -> ChatMessageDraft {
        ChatMessageDraft(clientID: clientID, kind: .text, text: text)
    }
}

public enum ChatRules {
    /// Höchstlänge einer Textnachricht (wie auf dem Server).
    public static let maximumTextLength = 2_000
    /// Nachrichten je Seite beim Laden des Verlaufs.
    public static let pageSize = 40

    /// Getrimmter Text oder `nil`, wenn leer bzw. zu lang.
    public static func validText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumTextLength else { return nil }
        return trimmed
    }
}

/// Unterhaltungen und Nachrichten. Zugriff prüft der Server: direkte Chats nur unter Freunden ohne Blockierung,
/// Gruppenchats nur für aktuelle Mitglieder.
public protocol ChatRepository: Sendable {
    /// Alle Unterhaltungen (direkte Chats mit Nachrichten und alle Gruppenchats), neueste zuerst.
    func conversations() async throws -> [ConversationSummary]
    /// Öffnet (oder legt an) den direkten Chat mit einem Freund.
    func openDirectConversation(with publicID: UUID) async throws -> ConversationSummary
    /// Chat einer Gruppe, in der man Mitglied ist.
    func groupConversation(for groupID: UUID) async throws -> ConversationSummary
    /// Nachrichten vor `before` (ohne Angabe: die neuesten), aufsteigend sortiert, höchstens `limit`.
    func messages(in conversationID: UUID, before: Date?, limit: Int) async throws -> [ChatMessage]
    /// Sendet eine Nachricht. Wiederholungen mit derselben `clientID` liefern die bereits gespeicherte Nachricht.
    func send(_ draft: ChatMessageDraft, to conversationID: UUID) async throws -> ChatMessage
    /// Markiert alles bis einschließlich `through` als gelesen.
    func markRead(_ conversationID: UUID, through: Date) async throws
    /// Löscht eine eigene Nachricht.
    func deleteMessage(_ messageID: UUID) async throws
    /// Meldet neue Nachrichten in einer Unterhaltung (Echtzeit). Endet sofort, wenn Echtzeit nicht verfügbar ist –
    /// dann aktualisiert die App regelmäßig.
    func messageEvents(in conversationID: UUID) -> AsyncStream<Void>
    /// Meldet Änderungen an irgendeiner Unterhaltung (für die Chatliste und Ungelesen-Zähler).
    func conversationEvents() -> AsyncStream<Void>
}
