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

    public init(
        id: UserID,
        publicID: UUID,
        username: String,
        displayName: String,
        municipalityID: RegionID?,
        regionalLeaderboardEnabled: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.publicID = publicID
        self.username = username
        self.displayName = displayName
        self.municipalityID = municipalityID
        self.regionalLeaderboardEnabled = regionalLeaderboardEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

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
}
