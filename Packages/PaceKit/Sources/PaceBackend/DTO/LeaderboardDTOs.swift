import Foundation
import PaceCore

/// Antwort von `leaderboard_page` und `leaderboard_neighborhood`.
struct LeaderboardResponse: Decodable, Equatable {
    let totalParticipants: Int
    let entries: [LeaderboardEntryRow]

    enum CodingKeys: String, CodingKey {
        case totalParticipants = "total_participants"
        case entries
    }
}

/// Eine Zeile im Ranking. Enthält nur öffentliche Felder.
struct LeaderboardEntryRow: Decodable, Equatable {
    let rank: Int
    let publicUserID: UUID
    let username: String
    let displayName: String
    let competitionSteps: Int
    let isCurrentUser: Bool
    /// Fehlt bei Servern ohne Migration 20261019100000.
    let avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case rank
        case publicUserID = "public_user_id"
        case username
        case displayName = "display_name"
        case competitionSteps = "competition_steps"
        case isCurrentUser = "is_current_user"
        case avatarPath = "avatar_path"
    }

    var entry: LeaderboardEntry {
        LeaderboardEntry(
            rank: rank,
            publicUserID: publicUserID,
            username: username,
            displayName: displayName,
            competitionSteps: competitionSteps,
            isCurrentUser: isCurrentUser,
            avatarPath: avatarPath
        )
    }
}

/// Parameter von `public.leaderboard_page`.
struct LeaderboardPageParams: Encodable {
    let regionID: String
    let period: String
    let date: String
    let limit: Int
    let offset: Int

    enum CodingKeys: String, CodingKey {
        case regionID = "p_region_id"
        case period = "p_period"
        case date = "p_date"
        case limit = "p_limit"
        case offset = "p_offset"
    }
}

/// Parameter von `public.leaderboard_neighborhood`.
struct LeaderboardNeighborhoodParams: Encodable {
    let regionID: String
    let period: String
    let date: String
    let radius: Int

    enum CodingKeys: String, CodingKey {
        case regionID = "p_region_id"
        case period = "p_period"
        case date = "p_date"
        case radius = "p_radius"
    }
}
