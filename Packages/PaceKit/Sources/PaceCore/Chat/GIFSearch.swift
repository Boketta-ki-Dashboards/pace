import Foundation

/// Ein GIF aus der Suche (z. B. GIPHY). Gesendet wird nie der fremde Link: Pace lädt die Datei herunter und schickt
/// sie wie ein GIF aus der Mediathek über den geschützten Chat-Speicher (Bucket `chat-media`) – sie bleibt damit auch
/// später verfügbar und ist nur für die Teilnehmer der Unterhaltung lesbar.
public struct GIFSearchResult: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    /// Kleines Standbild für das Raster (spart Arbeitsspeicher gegenüber vielen animierten Vorschauen).
    public let stillURL: URL
    /// Datei zum Senden (animiertes GIF, unter der Größengrenze des Chats).
    public let sendURL: URL
    public let width: Int
    public let height: Int

    public init(id: String, title: String, stillURL: URL, sendURL: URL, width: Int, height: Int) {
        self.id = id
        self.title = title
        self.stillURL = stillURL
        self.sendURL = sendURL
        self.width = width
        self.height = height
    }

    /// Seitenverhältnis (Breite/Höhe) für das Raster; 1 bei fehlenden Maßen.
    public var aspectRatio: Double {
        guard width > 0, height > 0 else { return 1 }
        return Double(width) / Double(height)
    }
}

/// Fehler der GIF-Suche – jeweils mit eigenem, ehrlichem Hinweis in der App.
public enum GIFSearchError: Error, Equatable, Sendable {
    /// Kein API-Schlüssel eingerichtet oder vom Anbieter abgelehnt.
    case notConfigured
    /// Keine Verbindung zum Internet.
    case offline
    /// Zu viele Anfragen in kurzer Zeit (Kontingent des Schlüssels).
    case rateLimited
    /// Die Datei ist zu groß oder kein GIF.
    case unsuitableFile
    /// Sonstiger Fehler beim Anbieter.
    case failed
}

/// Suche nach GIFs bei einem externen Anbieter.
public protocol GIFSearching: Sendable {
    /// Pflichtangabe der Quelle, z. B. „Powered by GIPHY“.
    var attribution: String { get }
    /// Wohin Suchbegriffe gehen – für den Datenschutzhinweis im Auswahlfenster.
    var privacyNote: String { get }
    /// Beliebte GIFs (Startansicht ohne Suchbegriff).
    func trending(limit: Int, offset: Int) async throws(GIFSearchError) -> [GIFSearchResult]
    func search(_ query: String, limit: Int, offset: Int) async throws(GIFSearchError) -> [GIFSearchResult]
    /// Lädt die Datei zum Senden (geprüft: GIF, höchstens `maximumBytes`).
    func download(_ result: GIFSearchResult, maximumBytes: Int) async throws(GIFSearchError) -> Data
}

public enum GIFRules {
    /// Suchbegriffe werden gekürzt (Anbieter begrenzen die Länge, lange Texte ergeben keine Treffer).
    public static let maximumQueryLength = 50
    /// So viele GIFs je Seite.
    public static let pageSize = 30
    /// Höchstens so viele GIFs werden nachgeladen (Arbeitsspeicher, Kontingent).
    public static let maximumResults = 150

    /// Bereinigter Suchbegriff; `nil` für leere Eingaben (dann zeigt die Auswahl beliebte GIFs).
    public static func query(_ text: String) -> String? {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        let limited = String(collapsed.prefix(maximumQueryLength)).trimmingCharacters(in: .whitespaces)
        return limited.isEmpty ? nil : limited
    }

    /// Die Daten sind ein GIF (Signatur `GIF87a` bzw. `GIF89a`).
    public static func isGIF(_ data: Data) -> Bool {
        let signature = Array(data.prefix(6))
        return signature == Array("GIF87a".utf8) || signature == Array("GIF89a".utf8)
    }
}
