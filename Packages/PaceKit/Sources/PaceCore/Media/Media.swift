import Foundation

/// Speicherorte für Bilder in Supabase Storage. Alle Buckets sind privat: Lesen nur für angemeldete Nutzer mit
/// Berechtigung (Profilbilder: alle Angemeldeten; Gruppenbilder: Mitglieder und Eingeladene; Chat-Medien: Teilnehmer).
public enum MediaBucket: String, Codable, Sendable, CaseIterable {
    case avatars
    case groupImages = "group-images"
    case chatMedia = "chat-media"
}

/// Verweis auf eine gespeicherte Datei: Bucket und Pfad darin (z. B. `<public_id>/<uuid>.jpg`).
public struct MediaReference: Hashable, Codable, Sendable {
    public let bucket: MediaBucket
    public let path: String

    public init(bucket: MediaBucket, path: String) {
        self.bucket = bucket
        self.path = path
    }

    public static func avatar(_ path: String?) -> MediaReference? {
        path.map { MediaReference(bucket: .avatars, path: $0) }
    }

    public static func groupImage(_ path: String?) -> MediaReference? {
        path.map { MediaReference(bucket: .groupImages, path: $0) }
    }

    public static func chatMedia(_ path: String?) -> MediaReference? {
        path.map { MediaReference(bucket: .chatMedia, path: $0) }
    }
}

/// Wohin ein neues Bild hochgeladen wird. Der Pfad (Ordner) ergibt sich daraus; der Dateiname ist zufällig.
public enum MediaUploadTarget: Equatable, Sendable {
    /// Eigenes Profilbild (Ordner = eigene öffentliche ID).
    case avatar
    /// Bild einer Gruppe (nur wer die Gruppe verwaltet).
    case groupImage(groupID: UUID)
    /// Anhang in einer Unterhaltung (nur Teilnehmer): Bild, GIF oder Sprachnachricht.
    case chat(conversationID: UUID)
}

/// Erlaubte Formate und Größen für Uploads (gleiche Grenzen wie die Buckets auf dem Server).
public enum MediaRules {
    /// Bildformate (alle Buckets).
    public static let allowedContentTypes: Set<String> = ["image/jpeg", "image/png", "image/gif", "image/heic", "image/webp"]
    /// Audioformate für Sprachnachrichten (nur `chat-media`, Migration 20261023100100): AAC in MP4/M4A bzw. roh.
    public static let allowedAudioContentTypes: Set<String> = ["audio/mp4", "audio/x-m4a", "audio/aac"]
    /// Inhaltstyp, mit dem die App Sprachnachrichten hochlädt (Aufnahme als AAC in .m4a).
    public static let voiceContentType = "audio/mp4"

    /// Erlaubte Inhaltstypen je Ziel: Bilder überall, Audio zusätzlich in Unterhaltungen.
    public static func allowedContentTypes(for target: MediaUploadTarget) -> Set<String> {
        switch target {
        case .chat: allowedContentTypes.union(allowedAudioContentTypes)
        case .avatar, .groupImage: allowedContentTypes
        }
    }

    public static func isAudio(_ contentType: String) -> Bool {
        allowedAudioContentTypes.contains(contentType.lowercased())
    }

    /// 10 MB für Chat-Bilder, GIFs und Sprachnachrichten (5 Minuten AAC liegen weit darunter), 5 MB für Profil- und
    /// Gruppenbilder.
    public static func maximumBytes(for target: MediaUploadTarget) -> Int {
        switch target {
        case .chat: maximumChatBytes
        case .avatar, .groupImage: 5 * 1024 * 1024
        }
    }

    /// Größengrenze für Chat-Anhänge (wie im Bucket `chat-media`).
    public static let maximumChatBytes = 10 * 1024 * 1024
}

public enum MediaError: Error, Equatable, Sendable {
    case tooLarge
    case unsupportedType
    case notAllowed
    case notFound
    case network
    case unavailable
    case unexpected(String)
}

/// Hochladen und Laden von Bildern und Sprachnachrichten (Supabase Storage, private Buckets).
public protocol MediaRepository: Sendable {
    /// Lädt Daten hoch und gibt den Verweis zurück. Prüft Format und Größe vorab.
    func upload(_ data: Data, contentType: String, to target: MediaUploadTarget) async throws -> MediaReference
    /// Lädt eine Datei (mit Berechtigungsprüfung auf dem Server).
    func data(for reference: MediaReference) async throws -> Data
    /// Löscht eine eigene Datei (z. B. altes Profilbild, vor dem Löschen des Kontos).
    func delete(_ reference: MediaReference) async throws
}
