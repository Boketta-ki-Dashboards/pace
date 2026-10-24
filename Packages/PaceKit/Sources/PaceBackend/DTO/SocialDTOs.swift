import Foundation
import PaceCore

// Antworten der Social-RPCs (siehe docs/SOCIAL.md). Alle Felder sind öffentlich; Zeitstempel kommen als
// `timestamptz`-String, Tage als `YYYY-MM-DD`.

struct SocialProfileRow: Decodable {
    let publicID: UUID
    let username: String
    let displayName: String
    /// Fehlt bei Servern ohne Migration 20261019100000.
    let avatarPath: String?
    /// Eigener Spitzname des Aufrufers; fehlt bei Servern ohne Migration 20261023100000.
    let nickname: String?

    enum CodingKeys: String, CodingKey {
        case publicID = "public_id"
        case username
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case nickname
    }

    var profile: SocialProfile {
        SocialProfile(publicID: publicID, username: username, displayName: displayName, avatarPath: avatarPath, nickname: nickname)
    }
}

struct ProfileSearchRow: Decodable {
    let profile: SocialProfileRow
    let relationship: String
    let requestID: UUID?

    enum CodingKeys: String, CodingKey {
        case relationship
        case requestID = "request_id"
    }

    init(from decoder: Decoder) throws {
        profile = try SocialProfileRow(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relationship = try container.decode(String.self, forKey: .relationship)
        requestID = try container.decodeIfPresent(UUID.self, forKey: .requestID)
    }

    var result: ProfileSearchResult {
        ProfileSearchResult(
            profile: profile.profile,
            relationship: SocialRelationship(rawValue: relationship) ?? .none,
            requestID: requestID
        )
    }
}

struct FriendRequestOutcomeRow: Decodable {
    let status: String
}

struct FriendRequestRow: Decodable {
    let id: UUID
    let direction: String
    let profile: SocialProfileRow
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "request_id"
        case direction
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        profile = try SocialProfileRow(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        direction = try container.decode(String.self, forKey: .direction)
        createdAt = try container.decodeTimestamp(forKey: .createdAt)
    }

    var request: FriendRequest {
        FriendRequest(id: id, direction: direction == "incoming" ? .incoming : .outgoing, profile: profile.profile, createdAt: createdAt)
    }
}

struct FriendRow: Decodable {
    let profile: SocialProfileRow
    let friendsSince: Date

    enum CodingKeys: String, CodingKey {
        case friendsSince = "friends_since"
    }

    init(from decoder: Decoder) throws {
        profile = try SocialProfileRow(from: decoder)
        friendsSince = try decoder.container(keyedBy: CodingKeys.self).decodeTimestamp(forKey: .friendsSince)
    }

    var friend: Friend {
        Friend(profile: profile.profile, friendsSince: friendsSince)
    }
}

struct FriendProfileRow: Decodable {
    let profile: SocialProfileRow
    let friendsSince: Date
    let stepsToday: Int
    let stepsWeek: Int

    enum CodingKeys: String, CodingKey {
        case friendsSince = "friends_since"
        case stepsToday = "steps_today"
        case stepsWeek = "steps_week"
    }

    init(from decoder: Decoder) throws {
        profile = try SocialProfileRow(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        friendsSince = try container.decodeTimestamp(forKey: .friendsSince)
        stepsToday = try container.decode(Int.self, forKey: .stepsToday)
        stepsWeek = try container.decode(Int.self, forKey: .stepsWeek)
    }

    var details: FriendProfileDetails {
        FriendProfileDetails(profile: profile.profile, friendsSince: friendsSince, stepsToday: stepsToday, stepsWeek: stepsWeek)
    }
}

struct GroupSummaryRow: Decodable {
    let id: UUID
    let name: String
    let description: String
    let kind: String
    let role: String
    let memberCount: Int
    let dailyGoal: Int
    let nextDailyGoal: Int?
    let timeZone: String
    let groupToday: LocalDate
    let inviteCode: String
    let currentStreak: Int
    let bestStreak: Int
    let todayReachedCount: Int
    let todayRequiredCount: Int
    let todayComplete: Bool
    let createdAt: Date
    let imagePath: String?
    let privacy: GroupPrivacy

    enum CodingKeys: String, CodingKey {
        case id = "group_id"
        case name
        case description
        case kind
        case role
        case memberCount = "member_count"
        case dailyGoal = "daily_goal"
        case nextDailyGoal = "next_daily_goal"
        case timeZone = "time_zone"
        case groupToday = "group_today"
        case inviteCode = "invite_code"
        case currentStreak = "current_streak"
        case bestStreak = "best_streak"
        case todayReachedCount = "today_reached_count"
        case todayRequiredCount = "today_required_count"
        case todayComplete = "today_complete"
        case createdAt = "created_at"
        case imagePath = "image_path"
        case privacy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        kind = try container.decode(String.self, forKey: .kind)
        role = try container.decode(String.self, forKey: .role)
        memberCount = try container.decode(Int.self, forKey: .memberCount)
        dailyGoal = try container.decode(Int.self, forKey: .dailyGoal)
        nextDailyGoal = try container.decodeIfPresent(Int.self, forKey: .nextDailyGoal)
        timeZone = try container.decode(String.self, forKey: .timeZone)
        groupToday = try container.decode(LocalDate.self, forKey: .groupToday)
        inviteCode = try container.decode(String.self, forKey: .inviteCode)
        currentStreak = try container.decode(Int.self, forKey: .currentStreak)
        bestStreak = try container.decode(Int.self, forKey: .bestStreak)
        todayReachedCount = try container.decode(Int.self, forKey: .todayReachedCount)
        todayRequiredCount = try container.decode(Int.self, forKey: .todayRequiredCount)
        todayComplete = try container.decode(Bool.self, forKey: .todayComplete)
        createdAt = try container.decodeTimestamp(forKey: .createdAt)
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        // Vor Migration 20261019100100 gibt es nur Gruppen mit Einladungscode.
        privacy = try container.decodeIfPresent(String.self, forKey: .privacy).flatMap(GroupPrivacy.init(rawValue:)) ?? .code
    }

    var summary: GroupSummary {
        GroupSummary(
            id: id,
            name: name,
            description: description,
            kind: GroupKind(rawValue: kind) ?? .other,
            role: role == "owner" ? .owner : .member,
            memberCount: memberCount,
            dailyGoal: dailyGoal,
            nextDailyGoal: nextDailyGoal,
            timeZone: timeZone,
            groupToday: groupToday,
            inviteCode: inviteCode,
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            todayReachedCount: todayReachedCount,
            todayRequiredCount: todayRequiredCount,
            todayComplete: todayComplete,
            createdAt: createdAt,
            imagePath: imagePath,
            privacy: privacy
        )
    }
}

struct GroupRankingResponse: Decodable {
    let totalParticipants: Int
    let groupToday: LocalDate
    let dailyGoal: Int
    let entries: [GroupRankingRow]

    enum CodingKeys: String, CodingKey {
        case totalParticipants = "total_participants"
        case groupToday = "group_today"
        case dailyGoal = "daily_goal"
        case entries
    }

    var ranking: GroupRanking {
        GroupRanking(
            totalParticipants: totalParticipants,
            groupToday: groupToday,
            dailyGoal: dailyGoal,
            entries: entries.map(\.entry).sorted { $0.rank < $1.rank }
        )
    }
}

struct GroupRankingRow: Decodable {
    let rank: Int
    let publicUserID: UUID
    let username: String
    let displayName: String
    let competitionSteps: Int
    let isCurrentUser: Bool
    let role: String
    let reachedGoalToday: Bool
    let avatarPath: String?
    let nickname: String?

    enum CodingKeys: String, CodingKey {
        case rank
        case publicUserID = "public_user_id"
        case username
        case displayName = "display_name"
        case competitionSteps = "competition_steps"
        case isCurrentUser = "is_current_user"
        case role
        case reachedGoalToday = "reached_goal_today"
        case avatarPath = "avatar_path"
        case nickname
    }

    var entry: GroupRankingEntry {
        GroupRankingEntry(
            rank: rank,
            profile: SocialProfile(
                publicID: publicUserID,
                username: username,
                displayName: displayName,
                avatarPath: avatarPath,
                nickname: nickname
            ),
            competitionSteps: competitionSteps,
            isCurrentUser: isCurrentUser,
            role: role == "owner" ? .owner : .member,
            reachedGoalToday: reachedGoalToday
        )
    }
}

struct GroupDayRow: Decodable {
    let day: LocalDate
    let memberCount: Int
    let requiredCount: Int
    let reachedCount: Int
    let dailyGoal: Int
    let reached: Bool
    let isToday: Bool

    enum CodingKeys: String, CodingKey {
        case day
        case memberCount = "member_count"
        case requiredCount = "required_count"
        case reachedCount = "reached_count"
        case dailyGoal = "daily_goal"
        case reached
        case isToday = "is_today"
    }

    var groupDay: GroupDay {
        GroupDay(
            day: day,
            memberCount: memberCount,
            requiredCount: requiredCount,
            reachedCount: reachedCount,
            dailyGoal: dailyGoal,
            reached: reached,
            isToday: isToday
        )
    }
}

struct GroupInvitationRow: Decodable {
    let id: UUID
    let groupID: UUID
    let groupName: String
    let groupKind: String
    let memberCount: Int
    let inviterUsername: String
    let inviterDisplayName: String
    let createdAt: Date
    let groupImagePath: String?
    let inviterNickname: String?

    enum CodingKeys: String, CodingKey {
        case id = "invitation_id"
        case groupID = "group_id"
        case groupName = "group_name"
        case groupKind = "group_kind"
        case memberCount = "member_count"
        case inviterUsername = "inviter_username"
        case inviterDisplayName = "inviter_display_name"
        case createdAt = "created_at"
        case groupImagePath = "group_image_path"
        case inviterNickname = "inviter_nickname"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        groupID = try container.decode(UUID.self, forKey: .groupID)
        groupName = try container.decode(String.self, forKey: .groupName)
        groupKind = try container.decode(String.self, forKey: .groupKind)
        memberCount = try container.decode(Int.self, forKey: .memberCount)
        inviterUsername = try container.decode(String.self, forKey: .inviterUsername)
        inviterDisplayName = try container.decode(String.self, forKey: .inviterDisplayName)
        createdAt = try container.decodeTimestamp(forKey: .createdAt)
        groupImagePath = try container.decodeIfPresent(String.self, forKey: .groupImagePath)
        inviterNickname = try container.decodeIfPresent(String.self, forKey: .inviterNickname)
    }

    var invitation: GroupInvitation {
        GroupInvitation(
            id: id,
            groupID: groupID,
            groupName: groupName,
            groupKind: GroupKind(rawValue: groupKind) ?? .other,
            memberCount: memberCount,
            inviterUsername: inviterUsername,
            inviterDisplayName: inviterDisplayName,
            createdAt: createdAt,
            groupImagePath: groupImagePath,
            inviterNickname: inviterNickname
        )
    }
}

struct OutgoingInvitationRow: Decodable {
    let id: UUID
    let profile: SocialProfileRow
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "invitation_id"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        profile = try SocialProfileRow(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decodeTimestamp(forKey: .createdAt)
    }

    var invitation: OutgoingGroupInvitation {
        OutgoingGroupInvitation(id: id, profile: profile.profile, createdAt: createdAt)
    }
}

struct GroupInviteOutcomeRow: Decodable {
    let status: String
}

struct InvitationResponseRow: Decodable {
    let status: String
    let group: GroupSummaryRow?
}

/// Antwort von `social_public_profile`.
struct PublicProfileRow: Decodable {
    let profile: SocialProfileRow
    let relationship: String
    let requestID: UUID?
    let friendsSince: Date?
    let stepsToday: Int?
    let stepsWeek: Int?
    let isBlockedByMe: Bool

    enum CodingKeys: String, CodingKey {
        case relationship
        case requestID = "request_id"
        case friendsSince = "friends_since"
        case stepsToday = "steps_today"
        case stepsWeek = "steps_week"
        case isBlockedByMe = "is_blocked_by_me"
    }

    init(from decoder: Decoder) throws {
        profile = try SocialProfileRow(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relationship = try container.decode(String.self, forKey: .relationship)
        requestID = try container.decodeIfPresent(UUID.self, forKey: .requestID)
        friendsSince = try container.decodeTimestampIfPresent(forKey: .friendsSince)
        stepsToday = try container.decodeIfPresent(Int.self, forKey: .stepsToday)
        stepsWeek = try container.decodeIfPresent(Int.self, forKey: .stepsWeek)
        isBlockedByMe = try container.decodeIfPresent(Bool.self, forKey: .isBlockedByMe) ?? false
    }

    var publicProfile: PublicProfile {
        PublicProfile(
            profile: profile.profile,
            relationship: SocialRelationship(rawValue: relationship) ?? .none,
            requestID: requestID,
            friendsSince: friendsSince,
            stepsToday: stepsToday,
            stepsWeek: stepsWeek,
            isBlockedByMe: isBlockedByMe
        )
    }
}

// MARK: - Gruppenkalender (Migration 20261023100200)

/// Antwort von `social_group_calendar`.
struct GroupCalendarResponse: Decodable {
    let groupID: UUID
    let timeZone: String
    let groupToday: LocalDate
    let firstGroupDay: LocalDate
    let days: [GroupCalendarDayRow]

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case timeZone = "time_zone"
        case groupToday = "group_today"
        case firstGroupDay = "first_group_day"
        case days
    }

    var calendar: GroupCalendar {
        GroupCalendar(
            groupID: groupID,
            timeZone: timeZone,
            groupToday: groupToday,
            firstGroupDay: firstGroupDay,
            days: days.map(\.day).sorted { $0.day < $1.day }
        )
    }
}

struct GroupCalendarDayRow: Decodable {
    let date: LocalDate
    let dailyGoal: Int?
    let memberCount: Int
    let requiredCount: Int
    let reachedCount: Int
    let secured: Bool
    let hasData: Bool
    let isToday: Bool
    let ranking: [GroupCalendarEntryRow]

    enum CodingKeys: String, CodingKey {
        case date = "day"
        case dailyGoal = "daily_goal"
        case memberCount = "member_count"
        case requiredCount = "required_count"
        case reachedCount = "reached_count"
        case secured
        case hasData = "has_data"
        case isToday = "is_today"
        case ranking
    }

    var day: GroupCalendarDay {
        GroupCalendarDay(
            day: date,
            dailyGoal: dailyGoal,
            memberCount: memberCount,
            requiredCount: requiredCount,
            reachedCount: reachedCount,
            secured: secured,
            hasData: hasData,
            isToday: isToday,
            ranking: ranking.map(\.entry).sorted { $0.rank < $1.rank }
        )
    }
}

/// Zeile der Tagesrangliste: Profilfelder (wie `SocialProfileRow`) plus Platz, Schritte, erreicht. Profilfelder `null`:
/// ehemaliges Mitglied, das mich blockiert hat (anonymisiert).
struct GroupCalendarEntryRow: Decodable {
    let profile: SocialProfileRow?
    let rank: Int
    let competitionSteps: Int
    let reached: Bool
    let isCurrentUser: Bool

    enum CodingKeys: String, CodingKey {
        case publicID = "public_id"
        case rank
        case competitionSteps = "competition_steps"
        case reached
        case isCurrentUser = "is_current_user"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decodeIfPresent(UUID.self, forKey: .publicID) == nil ? nil : SocialProfileRow(from: decoder)
        rank = try container.decode(Int.self, forKey: .rank)
        competitionSteps = try container.decode(Int.self, forKey: .competitionSteps)
        reached = try container.decode(Bool.self, forKey: .reached)
        isCurrentUser = try container.decode(Bool.self, forKey: .isCurrentUser)
    }

    var entry: GroupCalendarEntry {
        GroupCalendarEntry(
            rank: rank,
            profile: profile?.profile,
            competitionSteps: competitionSteps,
            reached: reached,
            isCurrentUser: isCurrentUser
        )
    }
}
