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
    /// Sprachnachricht (AAC in .m4a, Bucket `chat-media`, höchstens `ChatRules.maximumVoiceDuration`).
    case voice
}

/// Kurzfassung der letzten Nachricht für die Chatliste.
public struct ChatMessagePreview: Equatable, Sendable {
    public let kind: ChatMessageKind
    /// Text der Nachricht (bei Bildern/GIFs/Profilen/Sprachnachrichten `nil`).
    public let text: String?
    /// Anzeigename des Absenders; `nil` bei eigenen Nachrichten.
    public let senderName: String?
    public let isOwn: Bool
    public let sentAt: Date
    /// Eigener Spitzname für den Absender; `nil` bei eigenen Nachrichten oder ohne Spitznamen.
    public let senderNickname: String?
    /// Dauer bei Sprachnachrichten („Sprachnachricht · 0:18“).
    public let mediaDuration: Duration?

    public init(
        kind: ChatMessageKind,
        text: String?,
        senderName: String?,
        isOwn: Bool,
        sentAt: Date,
        senderNickname: String? = nil,
        mediaDuration: Duration? = nil
    ) {
        self.kind = kind
        self.text = text
        self.senderName = senderName
        self.isOwn = isOwn
        self.sentAt = sentAt
        self.senderNickname = senderNickname
        self.mediaDuration = mediaDuration
    }

    /// Angezeigter Absendername: eigener Spitzname, sonst Anzeigename; `nil` bei eigenen Nachrichten bzw. ohne Konto.
    public var shownSenderName: String? {
        senderName.map { NicknameRules.shownName(nickname: senderNickname, displayName: $0) }
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
    /// Darf Nachrichten anpinnen: im Gruppenchat nur der Gruppen-Owner, im Privatchat beide, solange sie schreiben
    /// dürfen (Migration 20261023100100; ältere Server: `false`).
    public let canPin: Bool

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
        updatedAt: Date,
        canPin: Bool = false
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
        self.canPin = canPin
    }

    /// Angezeigter Titel: bei Privatchats der eigene Spitzname für das Gegenüber, sonst `title`.
    public var shownTitle: String {
        guard kind == .direct, let nickname = peer?.nickname, !nickname.isEmpty else { return title }
        return nickname
    }

    /// Bild für die Liste: Profilbild des Freundes bzw. Gruppenbild.
    public var image: MediaReference? {
        switch kind {
        case .direct: peer?.avatar
        case .group: .groupImage(groupImagePath)
        }
    }
}

/// Kompakte Vorschau der Nachricht, auf die geantwortet wird (Verweis in der Blase, Sprung zum Original).
public struct ChatReplyPreview: Equatable, Sendable, Identifiable {
    /// ID des Originals (zum Springen, solange es geladen bzw. ladbar ist).
    public let id: UUID
    /// Absender des Originals (mit eigenem Spitznamen); `nil`, wenn gelöscht/verborgen oder das Konto fehlt.
    public let sender: SocialProfile?
    public let kind: ChatMessageKind
    /// Gekürzter Text (höchstens `ChatRules.replyPreviewLength` Zeichen) bei Textnachrichten.
    public let text: String?
    /// Dauer, wenn das Original eine Sprachnachricht ist.
    public let mediaDuration: Duration?
    /// Original gelöscht oder für mich nicht sichtbar (z. B. von einer blockierten Person) – Inhalt fehlt.
    public let isDeleted: Bool

    public init(id: UUID, sender: SocialProfile?, kind: ChatMessageKind, text: String?, mediaDuration: Duration?, isDeleted: Bool) {
        self.id = id
        self.sender = sender
        self.kind = kind
        self.text = text
        self.mediaDuration = mediaDuration
        self.isDeleted = isDeleted
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
    /// Vorschau der Nachricht, auf die geantwortet wird.
    public let replyPreview: ChatReplyPreview?
    /// Zeitpunkt der letzten Bearbeitung („Bearbeitet“).
    public let editedAt: Date?
    /// Dauer einer Sprachnachricht.
    public let mediaDuration: Duration?
    /// Eigener, privater Favorit.
    public let isFavorite: Bool
    /// In der Unterhaltung angepinnt (für alle Teilnehmer).
    public let isPinned: Bool

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
        sentAt: Date,
        replyPreview: ChatReplyPreview? = nil,
        editedAt: Date? = nil,
        mediaDuration: Duration? = nil,
        isFavorite: Bool = false,
        isPinned: Bool = false
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
        self.replyPreview = replyPreview
        self.editedAt = editedAt
        self.mediaDuration = mediaDuration
        self.isFavorite = isFavorite
        self.isPinned = isPinned
    }

    public var isEdited: Bool { editedAt != nil }

    /// Bearbeiten ist nur für eigene Textnachrichten möglich (der Server prüft zusätzlich das Schreibrecht).
    public var canEdit: Bool { isOwn && kind == .text }

    /// Gleiche Nachricht mit geändertem Favoriten-Status (z. B. sofort nach dem Antippen).
    public func withFavorite(_ isFavorite: Bool) -> ChatMessage {
        ChatMessage(
            id: id, conversationID: conversationID, clientID: clientID, sender: sender, isOwn: isOwn, kind: kind,
            text: text, media: media, sharedProfile: sharedProfile, sentAt: sentAt, replyPreview: replyPreview,
            editedAt: editedAt, mediaDuration: mediaDuration, isFavorite: isFavorite, isPinned: isPinned
        )
    }

    /// Gleiche Nachricht mit geändertem Pin-Status.
    public func withPinned(_ isPinned: Bool) -> ChatMessage {
        ChatMessage(
            id: id, conversationID: conversationID, clientID: clientID, sender: sender, isOwn: isOwn, kind: kind,
            text: text, media: media, sharedProfile: sharedProfile, sentAt: sentAt, replyPreview: replyPreview,
            editedAt: editedAt, mediaDuration: mediaDuration, isFavorite: isFavorite, isPinned: isPinned
        )
    }
}

/// Eine angepinnte Nachricht (Hinweis oben im Chat; Antippen springt zur Nachricht).
public struct ChatPin: Equatable, Sendable, Identifiable {
    public let message: ChatMessage
    /// Wer angepinnt hat; `nil`, wenn das Konto gelöscht wurde.
    public let pinnedBy: SocialProfile?
    public let pinnedAt: Date

    public init(message: ChatMessage, pinnedBy: SocialProfile?, pinnedAt: Date) {
        self.message = message
        self.pinnedBy = pinnedBy
        self.pinnedAt = pinnedAt
    }

    public var id: UUID { message.id }
}

/// Echtzeit-Hinweis in einer Unterhaltung – ohne Inhalt; die App lädt danach über die RPCs.
public enum ChatConversationEvent: String, Sendable, CaseIterable {
    /// Neue oder gelöschte Nachricht.
    case message
    /// Eine Nachricht wurde bearbeitet.
    case messageUpdated = "message_updated"
    /// Die angepinnten Nachrichten haben sich geändert.
    case pinsChanged = "pins_changed"
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
    /// Nachricht, auf die geantwortet wird (gleiche Unterhaltung, sichtbar).
    public let replyToID: UUID?
    /// Dauer einer Sprachnachricht (`kind == .voice`).
    public let mediaDuration: Duration?

    public init(
        clientID: UUID = UUID(),
        kind: ChatMessageKind,
        text: String? = nil,
        mediaPath: String? = nil,
        sharedProfileID: UUID? = nil,
        replyToID: UUID? = nil,
        mediaDuration: Duration? = nil
    ) {
        self.clientID = clientID
        self.kind = kind
        self.text = text
        self.mediaPath = mediaPath
        self.sharedProfileID = sharedProfileID
        self.replyToID = replyToID
        self.mediaDuration = mediaDuration
    }

    public static func text(_ text: String, clientID: UUID = UUID(), replyTo replyToID: UUID? = nil) -> ChatMessageDraft {
        ChatMessageDraft(clientID: clientID, kind: .text, text: text, replyToID: replyToID)
    }

    /// Sprachnachricht mit vorher hochgeladener Datei (`MediaUploadTarget.chat`, Typ `MediaRules.voiceContentType`).
    public static func voice(mediaPath: String, duration: Duration, clientID: UUID = UUID(), replyTo replyToID: UUID? = nil) -> ChatMessageDraft {
        ChatMessageDraft(clientID: clientID, kind: .voice, mediaPath: mediaPath, replyToID: replyToID, mediaDuration: duration)
    }
}

public enum ChatRules {
    /// Höchstlänge einer Textnachricht (wie auf dem Server).
    public static let maximumTextLength = 2_000
    /// Nachrichten je Seite beim Laden des Verlaufs.
    public static let pageSize = 40
    /// Höchstdauer einer Sprachnachricht (wie auf dem Server: 300 000 ms).
    public static let maximumVoiceDuration: Duration = .seconds(300)
    /// Höchstzahl angepinnter Nachrichten je Unterhaltung (wie auf dem Server).
    public static let maximumPinnedMessages = 5
    /// Länge, auf die der Server den Text in einer Antwort-Vorschau kürzt.
    public static let replyPreviewLength = 200

    /// Ganze Millisekunden (gerundet) – so überträgt der Server Dauern.
    public static func milliseconds(of duration: Duration) -> Int {
        let components = duration.components
        let value = Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
        return Int(value.rounded())
    }

    /// Dauer in Millisekunden für eine Sprachnachricht, oder `nil`, wenn sie unter 1 ms oder über
    /// `maximumVoiceDuration` liegt.
    public static func validVoiceMilliseconds(_ duration: Duration) -> Int? {
        let value = milliseconds(of: duration)
        guard value >= 1, value <= milliseconds(of: maximumVoiceDuration) else { return nil }
        return value
    }

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

    // MARK: Nachrichtenaktionen (Migration 20261023100100)

    /// Bearbeitet eine eigene Textnachricht (gleiche Längenregeln wie beim Senden) und liefert sie mit `editedAt`.
    /// `notFound` für fremde/gelöschte Nachrichten, `invalidInput` für andere Arten, `readOnly` ohne Schreibrecht.
    func editMessage(_ messageID: UUID, text: String) async throws -> ChatMessage
    /// Markiert eine sichtbare Nachricht als privaten Favoriten bzw. entfernt ihn (idempotent).
    func setFavorite(_ messageID: UUID, isFavorite: Bool) async throws
    /// Eigene Favoriten einer Unterhaltung, neueste Nachricht zuerst.
    func favorites(conversationID: UUID) async throws -> [ChatMessage]
    /// Pinnt eine Nachricht an bzw. löst sie und liefert alle Pins der Unterhaltung. Gruppenchat: nur der Owner
    /// (`notAllowed`); Privatchat: beide mit Schreibrecht (`readOnly`); höchstens `ChatRules.maximumPinnedMessages`
    /// (`pinLimitReached`).
    @discardableResult
    func setPinned(_ messageID: UUID, isPinned: Bool) async throws -> [ChatPin]
    /// Angepinnte Nachrichten einer Unterhaltung, zuletzt angepinnte zuerst.
    func pins(conversationID: UUID) async throws -> [ChatPin]
    /// Echtzeit-Hinweise einer Unterhaltung mit Art (neu/gelöscht, bearbeitet, Pins). Endet sofort, wenn Echtzeit
    /// nicht verfügbar ist – dann aktualisiert die App regelmäßig.
    func conversationActivity(in conversationID: UUID) -> AsyncStream<ChatConversationEvent>
}

public extension ChatRepository {
    /// Standards für Implementierungen ohne Nachrichtenaktionen (z. B. ältere Test-Doubles): nicht eingerichtet.
    func editMessage(_ messageID: UUID, text: String) async throws -> ChatMessage {
        throw SocialError.unavailable
    }

    func setFavorite(_ messageID: UUID, isFavorite: Bool) async throws {
        throw SocialError.unavailable
    }

    func favorites(conversationID: UUID) async throws -> [ChatMessage] {
        throw SocialError.unavailable
    }

    @discardableResult
    func setPinned(_ messageID: UUID, isPinned: Bool) async throws -> [ChatPin] {
        throw SocialError.unavailable
    }

    func pins(conversationID: UUID) async throws -> [ChatPin] {
        throw SocialError.unavailable
    }

    /// Ohne eigene Umsetzung: nur neue bzw. gelöschte Nachrichten (`messageEvents`).
    func conversationActivity(in conversationID: UUID) -> AsyncStream<ChatConversationEvent> {
        let events = messageEvents(in: conversationID)
        return AsyncStream { continuation in
            let task = Task {
                for await _ in events {
                    continuation.yield(.message)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
