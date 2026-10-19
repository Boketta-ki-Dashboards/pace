import Foundation
import PaceCore

/// Zeile aus `public.profiles` mit den Spalten aus `ProfileRow.columns`.
struct ProfileRow: Decodable, Equatable {
    /// Spaltenliste für `select`.
    static let columns = legacyColumns + ",avatar_path,is_discoverable"
    /// Spalten vor Migration 20261019100000 (ohne Profilbild und Auffindbarkeit). Fehlen die neuen Spalten auf dem
    /// Server, fragt das Repository mit dieser Liste erneut an.
    static let legacyColumns =
        "id,public_id,username,display_name,municipality_id,regional_leaderboard_enabled,created_at,updated_at"

    let id: UUID
    let publicID: UUID
    let username: String
    let displayName: String
    let municipalityID: String?
    let regionalLeaderboardEnabled: Bool
    let createdAt: Date
    let updatedAt: Date
    let avatarPath: String?
    let isDiscoverable: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case publicID = "public_id"
        case username
        case displayName = "display_name"
        case municipalityID = "municipality_id"
        case regionalLeaderboardEnabled = "regional_leaderboard_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case avatarPath = "avatar_path"
        case isDiscoverable = "is_discoverable"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        publicID = try container.decode(UUID.self, forKey: .publicID)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decode(String.self, forKey: .displayName)
        municipalityID = try container.decodeIfPresent(String.self, forKey: .municipalityID)
        regionalLeaderboardEnabled = try container.decode(Bool.self, forKey: .regionalLeaderboardEnabled)
        createdAt = try container.decodeTimestamp(forKey: .createdAt)
        updatedAt = try container.decodeTimestamp(forKey: .updatedAt)
        avatarPath = try container.decodeIfPresent(String.self, forKey: .avatarPath)
        isDiscoverable = try container.decodeIfPresent(Bool.self, forKey: .isDiscoverable) ?? true
    }

    var profile: UserProfile {
        UserProfile(
            id: UserID(id),
            publicID: publicID,
            username: username,
            displayName: displayName,
            municipalityID: municipalityID.map(RegionID.init(rawValue:)),
            regionalLeaderboardEnabled: regionalLeaderboardEnabled,
            createdAt: createdAt,
            updatedAt: updatedAt,
            avatarPath: avatarPath,
            isDiscoverable: isDiscoverable
        )
    }
}

/// Neues Profil. Weitere Spalten setzt der Server (Standardwerte, Trigger).
struct NewProfileRow: Encodable {
    let id: String
    let username: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
    }
}

/// Wechsel der Gemeinde, zusammen mit der Zustimmung zum Regionalranking.
struct ProfileRegionUpdate: Encodable {
    let municipalityID: String
    let regionalLeaderboardEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case municipalityID = "municipality_id"
        case regionalLeaderboardEnabled = "regional_leaderboard_enabled"
    }
}

/// Nur die Zustimmung zum Regionalranking.
struct ProfileOptInUpdate: Encodable {
    let regionalLeaderboardEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case regionalLeaderboardEnabled = "regional_leaderboard_enabled"
    }
}

/// Parameter von `public.is_username_available`.
struct UsernameAvailabilityParams: Encodable {
    let username: String

    enum CodingKeys: String, CodingKey {
        case username = "p_username"
    }
}

/// Benutzer- und/oder Anzeigename. Nicht gesetzte Werte bleiben unverändert (fehlen im Body).
struct ProfileNamesUpdate: Encodable {
    let username: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case username
        case displayName = "display_name"
    }
}

/// Profilbild setzen oder mit `null` entfernen.
struct ProfileAvatarUpdate: Encodable {
    let avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case avatarPath = "avatar_path"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Auch `nil` senden (als JSON-null), damit das Bild entfernt wird.
        try container.encode(avatarPath, forKey: .avatarPath)
    }
}

/// Auffindbarkeit in der Präfixsuche.
struct ProfileDiscoverableUpdate: Encodable {
    let isDiscoverable: Bool

    enum CodingKeys: String, CodingKey {
        case isDiscoverable = "is_discoverable"
    }
}
