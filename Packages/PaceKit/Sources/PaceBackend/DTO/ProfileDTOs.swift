import Foundation
import PaceCore

/// Zeile aus `public.profiles` mit den Spalten aus `ProfileRow.columns`.
struct ProfileRow: Decodable, Equatable {
    /// Spaltenliste für `select`.
    static let columns =
        "id,public_id,username,display_name,municipality_id,regional_leaderboard_enabled,created_at,updated_at"

    let id: UUID
    let publicID: UUID
    let username: String
    let displayName: String
    let municipalityID: String?
    let regionalLeaderboardEnabled: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case publicID = "public_id"
        case username
        case displayName = "display_name"
        case municipalityID = "municipality_id"
        case regionalLeaderboardEnabled = "regional_leaderboard_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
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
            updatedAt: updatedAt
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
