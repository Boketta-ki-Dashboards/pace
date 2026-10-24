import Foundation
import PaceCore

/// Eigene Nachricht, die noch nicht (oder nicht erfolgreich) beim Server angekommen ist. Sie bleibt mit derselben
/// `clientID` erhalten, damit „Erneut senden“ keine doppelte Nachricht erzeugt.
public struct PendingChatMessage: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// Bild oder GIF wird hochgeladen.
        case uploading
        case sending
        /// Fehlgeschlagen; Text für die Anzeige.
        case failed(String)
    }

    /// Bild oder GIF, das noch hochgeladen werden muss (bzw. für die Vorschau auf dem Gerät).
    public struct LocalMedia: Equatable, Sendable {
        public let data: Data
        public let contentType: String

        public init(data: Data, contentType: String) {
            self.data = data
            self.contentType = contentType
        }
    }

    public let clientID: UUID
    public let kind: ChatMessageKind
    public let text: String?
    public let localMedia: LocalMedia?
    /// Pfad im Bucket `chat-media`, sobald das Hochladen geklappt hat (beim erneuten Senden nicht noch einmal laden).
    public internal(set) var mediaPath: String?
    public let createdAt: Date
    public internal(set) var status: Status
    /// Nachricht, auf die geantwortet wird (Verweis in der Blase schon vor dem Senden).
    public let replyTo: ChatReplyPreview?
    /// Dauer einer Sprachnachricht.
    public let mediaDuration: Duration?

    public init(
        clientID: UUID,
        kind: ChatMessageKind,
        text: String?,
        localMedia: LocalMedia?,
        mediaPath: String?,
        createdAt: Date,
        status: Status,
        replyTo: ChatReplyPreview? = nil,
        mediaDuration: Duration? = nil
    ) {
        self.clientID = clientID
        self.kind = kind
        self.text = text
        self.localMedia = localMedia
        self.mediaPath = mediaPath
        self.createdAt = createdAt
        self.status = status
        self.replyTo = replyTo
        self.mediaDuration = mediaDuration
    }

    public var id: UUID { clientID }

    public var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    /// Muss vor dem Senden noch hochgeladen werden.
    var needsUpload: Bool {
        localMedia != nil && mediaPath == nil
    }

    var draft: ChatMessageDraft {
        ChatMessageDraft(
            clientID: clientID, kind: kind, text: text, mediaPath: mediaPath, replyToID: replyTo?.id, mediaDuration: mediaDuration
        )
    }
}

/// Eine Zeile im Verlauf: Nachricht vom Server, eigene ausstehende Nachricht oder eingeklappte Nachricht einer
/// blockierten Person.
public struct ChatTimelineEntry: Identifiable, Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case message(ChatMessage)
        case pending(PendingChatMessage)
        /// Nachricht einer Person, die du blockiert hast – eingeklappt, bis du sie aufdeckst.
        case blocked(ChatMessage)
    }

    public let id: String
    public let content: Content
    public let isOwn: Bool
    public let sender: SocialProfile?
    public let sentAt: Date
    /// Name und Profilbild über der Nachricht (fremde Nachrichten in Gruppen, erste eines Blocks).
    public internal(set) var showsSender: Bool
    /// Uhrzeit unter der Nachricht (letzte eines Blocks; bei ausstehenden Nachrichten der Status).
    public internal(set) var showsTime: Bool

    var isPendingContent: Bool {
        if case .pending = content { return true }
        return false
    }
}

/// Element des Verlaufs: Tages-Trenner oder Nachricht.
public enum ChatTimelineItem: Identifiable, Equatable, Sendable {
    case day(LocalDate, title: String)
    case entry(ChatTimelineEntry)

    public var id: String {
        switch self {
        case .day(let day, _): "day-\(day.isoString)"
        case .entry(let entry): entry.id
        }
    }
}

/// Baut aus Nachrichten den angezeigten Verlauf: chronologisch, mit Tages-Trennern und zu Blöcken zusammengefassten
/// aufeinanderfolgenden Nachrichten derselben Person (wie im Referenzbild: Name einmal oben, Uhrzeit einmal unten).
public enum ChatTimeline {
    /// Nachrichten derselben Person innerhalb dieses Abstands bilden einen Block.
    public static let groupingInterval: TimeInterval = 5 * 60

    public static func build(
        messages: [ChatMessage],
        pending: [PendingChatMessage],
        kind: ConversationKind,
        blockedUserIDs: Set<UUID>,
        revealedMessageIDs: Set<UUID>,
        calendar: ActivityCalendar,
        now: Date
    ) -> [ChatTimelineItem] {
        var entries: [ChatTimelineEntry] = messages.sorted(by: chronological).map { message in
            let isHidden = !message.isOwn
                && message.sender.map { blockedUserIDs.contains($0.publicID) } == true
                && !revealedMessageIDs.contains(message.id)
            return ChatTimelineEntry(
                id: "message-\(message.id.uuidString)",
                content: isHidden ? .blocked(message) : .message(message),
                isOwn: message.isOwn,
                sender: message.sender,
                sentAt: message.sentAt,
                showsSender: false,
                showsTime: false
            )
        }
        entries += pending.sorted { $0.createdAt < $1.createdAt }.map { message in
            ChatTimelineEntry(
                id: "pending-\(message.clientID.uuidString)",
                content: .pending(message),
                isOwn: true,
                sender: nil,
                sentAt: message.createdAt,
                showsSender: false,
                showsTime: true
            )
        }

        let today = calendar.day(containing: now)
        var items: [ChatTimelineItem] = []
        var currentDay: LocalDate?
        var previous: ChatTimelineEntry?
        for var entry in entries {
            let day = calendar.day(containing: entry.sentAt)
            let continuesBlock = previous.map { belongTogether($0, entry, calendar: calendar) } ?? false
            if !continuesBlock {
                closeBlock(in: &items)
            }
            // Ausstehende Nachrichten stehen immer am Ende – auch wenn die Uhr des Geräts etwas nachgeht, gibt es
            // dafür keinen Trenner zurück zu einem früheren Tag.
            let isBehind = currentDay.map { day < $0 } ?? false
            if day != currentDay, !(entry.isPendingContent && isBehind) {
                items.append(.day(day, title: ChatFormatting.dayTitle(day, today: today, calendar: calendar)))
                currentDay = day
            }
            if case .message = entry.content {
                entry.showsSender = kind == .group && !entry.isOwn && !continuesBlock
            }
            items.append(.entry(entry))
            previous = entry
        }
        closeBlock(in: &items)
        return items
    }

    /// Die letzte Nachricht eines Blocks zeigt die Uhrzeit.
    private static func closeBlock(in items: inout [ChatTimelineItem]) {
        guard case .entry(var last)? = items.last, case .message = last.content else { return }
        last.showsTime = true
        items[items.count - 1] = .entry(last)
    }

    /// Chronologisch; bei gleicher Zeit nach ID, damit die Reihenfolge stabil bleibt.
    public static func chronological(_ lhs: ChatMessage, _ rhs: ChatMessage) -> Bool {
        lhs.sentAt == rhs.sentAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.sentAt < rhs.sentAt
    }

    /// Zwei Nachrichten gehören zu einem Block: beide normale Nachrichten, gleiche Person, gleicher Tag, kurz
    /// hintereinander.
    static func belongTogether(_ previous: ChatTimelineEntry, _ next: ChatTimelineEntry, calendar: ActivityCalendar) -> Bool {
        guard case .message = previous.content, case .message = next.content else { return false }
        guard previous.isOwn == next.isOwn else { return false }
        if !next.isOwn {
            guard let lhs = previous.sender?.publicID, let rhs = next.sender?.publicID, lhs == rhs else { return false }
        }
        guard calendar.day(containing: previous.sentAt) == calendar.day(containing: next.sentAt) else { return false }
        return next.sentAt.timeIntervalSince(previous.sentAt) <= groupingInterval
    }
}
