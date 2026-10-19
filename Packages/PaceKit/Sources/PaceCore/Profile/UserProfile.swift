import Foundation

/// Das eigene Pace-Profil.
public struct UserProfile: Equatable, Sendable, Codable {
    public let id: UserID
    /// Öffentliche ID für Rankings. Unabhängig von der Auth-ID.
    public let publicID: UUID
    public var username: String
    public var displayName: String
    /// Feste ID der gewählten Gemeinde. Kreis, Bundesland und Land ergeben sich aus der Hierarchie.
    public var municipalityID: RegionID?
    /// Ob der Nutzer in öffentlichen Regionalrankings erscheinen möchte. Standard: aus.
    public var regionalLeaderboardEnabled: Bool
    public let createdAt: Date
    public var updatedAt: Date
    /// Profilbild im Bucket `avatars`.
    public var avatarPath: String?
    /// Ob andere das Profil über die Präfix-Suche finden (bei exakter Eingabe des Benutzernamens immer). Standard: an.
    public var isDiscoverable: Bool

    public init(
        id: UserID,
        publicID: UUID,
        username: String,
        displayName: String,
        municipalityID: RegionID?,
        regionalLeaderboardEnabled: Bool,
        createdAt: Date,
        updatedAt: Date,
        avatarPath: String? = nil,
        isDiscoverable: Bool = true
    ) {
        self.id = id
        self.publicID = publicID
        self.username = username
        self.displayName = displayName
        self.municipalityID = municipalityID
        self.regionalLeaderboardEnabled = regionalLeaderboardEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.avatarPath = avatarPath
        self.isDiscoverable = isDiscoverable
    }

    // Ältere Caches kennen die neuen Felder noch nicht.
    private enum CodingKeys: String, CodingKey {
        case id, publicID, username, displayName, municipalityID, regionalLeaderboardEnabled, createdAt, updatedAt
        case avatarPath, isDiscoverable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UserID.self, forKey: .id)
        publicID = try container.decode(UUID.self, forKey: .publicID)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decode(String.self, forKey: .displayName)
        municipalityID = try container.decodeIfPresent(RegionID.self, forKey: .municipalityID)
        regionalLeaderboardEnabled = try container.decode(Bool.self, forKey: .regionalLeaderboardEnabled)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        avatarPath = try container.decodeIfPresent(String.self, forKey: .avatarPath)
        isDiscoverable = try container.decodeIfPresent(Bool.self, forKey: .isDiscoverable) ?? true
    }

    public var avatar: MediaReference? { .avatar(avatarPath) }

    /// Ein Profil ist vollständig, sobald eine Region gewählt wurde. Benutzername und Anzeigename sind Pflichtfelder
    /// beim Anlegen.
    public var isComplete: Bool {
        municipalityID != nil
    }
}

/// Daten für das erstmalige Anlegen eines Profils.
public struct NewProfile: Equatable, Sendable {
    public let username: String
    public let displayName: String

    public init(username: String, displayName: String) {
        self.username = username
        self.displayName = displayName
    }
}

public enum ProfileError: Error, Equatable, Sendable {
    case usernameTaken
    case invalidUsername
    case invalidDisplayName
    case invalidRegion
    case notAuthenticated
    case network
    case rateLimited
    case unexpected(String)
}

/// Speichert und lädt das eigene Profil.
public protocol ProfileRepository: Sendable {
    /// `nil`, wenn für den Nutzer noch kein Profil existiert.
    func fetchProfile(for userID: UserID) async throws -> UserProfile?
    func createProfile(_ profile: NewProfile, for userID: UserID) async throws -> UserProfile
    func updateRegion(
        municipalityID: RegionID,
        regionalLeaderboardEnabled: Bool,
        for userID: UserID
    ) async throws -> UserProfile
    func updateRegionalLeaderboardEnabled(_ enabled: Bool, for userID: UserID) async throws -> UserProfile
    /// Ob ein Benutzername noch frei ist (Groß-/Kleinschreibung wird ignoriert).
    func isUsernameAvailable(_ username: String) async throws -> Bool
    /// Ändert Benutzernamen und/oder Anzeigenamen (`nil` = unverändert).
    func updateNames(username: String?, displayName: String?, for userID: UserID) async throws -> UserProfile
    /// Setzt oder entfernt das Profilbild (Pfad im Bucket `avatars`, vorher hochgeladen).
    func updateAvatar(path: String?, for userID: UserID) async throws -> UserProfile
    /// Ob das Profil in der Präfix-Suche erscheint.
    func updateDiscoverable(_ discoverable: Bool, for userID: UserID) async throws -> UserProfile
}

// Standard für Implementierungen ohne Profiländerungen (z. B. einfache Test-Doubles); die Supabase-Anbindung
// implementiert alle Methoden selbst.
extension ProfileRepository {
    public func updateNames(username: String?, displayName: String?, for userID: UserID) async throws -> UserProfile {
        throw ProfileError.unexpected("unsupported")
    }

    public func updateAvatar(path: String?, for userID: UserID) async throws -> UserProfile {
        throw ProfileError.unexpected("unsupported")
    }

    public func updateDiscoverable(_ discoverable: Bool, for userID: UserID) async throws -> UserProfile {
        throw ProfileError.unexpected("unsupported")
    }
}
