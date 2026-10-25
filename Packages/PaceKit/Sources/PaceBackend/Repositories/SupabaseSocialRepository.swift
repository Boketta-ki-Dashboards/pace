import Foundation
import PaceCore
import PostgREST

/// Freunde und Gruppen per RPC (siehe docs/SOCIAL.md). Clients haben keinen direkten Tabellenzugriff; alle Prüfungen
/// – Zugriff, Limits, Gruppen-Streak – erfolgen in den `security definer`-Funktionen auf dem Server.
struct SupabaseSocialRepository: SocialRepository {
    let client: PostgrestClient

    // MARK: Freunde

    func findProfile(username: String) async throws -> ProfileSearchResult? {
        let row: ProfileSearchRow? = try await mapped {
            try await client.rpc("social_find_profile", params: ["p_username": username]).execute().value
        }
        return row?.result
    }

    /// Unter 3 Zeichen fragt der Server nicht (leere Liste) – die Anfrage spart sich die App dann ganz.
    func searchProfiles(query: String) async throws -> [ProfileSearchResult] {
        var trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") {
            trimmed.removeFirst()
        }
        guard trimmed.count >= 3 else { return [] }
        let rows: [ProfileSearchRow] = try await mapped {
            try await client.rpc("social_search_profiles", params: ["p_query": trimmed]).execute().value
        }
        return rows.map(\.result)
    }

    func publicProfile(_ publicID: UUID, date: LocalDate) async throws -> PublicProfile {
        let row: PublicProfileRow = try await mapped {
            try await client.rpc(
                "social_public_profile",
                params: FriendProfileParams(publicID: publicID, date: date.isoString)
            ).execute().value
        }
        return row.publicProfile
    }

    func sendFriendRequest(to publicID: UUID) async throws -> FriendRequestOutcome {
        let row: FriendRequestOutcomeRow = try await mapped {
            try await client.rpc("social_send_friend_request", params: PublicIDParams(publicID: publicID)).execute().value
        }
        return FriendRequestOutcome(rawValue: row.status) ?? .requested
    }

    func respondToFriendRequest(_ requestID: UUID, accept: Bool) async throws {
        try await mapped {
            try await client.rpc(
                "social_respond_friend_request",
                params: RespondParams(idKey: .request, id: requestID, accept: accept)
            ).execute()
        }
    }

    func cancelFriendRequest(_ requestID: UUID) async throws {
        try await mapped {
            try await client.rpc("social_cancel_friend_request", params: ["p_request_id": requestID]).execute()
        }
    }

    func removeFriend(_ publicID: UUID) async throws {
        try await mapped {
            try await client.rpc("social_remove_friend", params: PublicIDParams(publicID: publicID)).execute()
        }
    }

    func friendRequests() async throws -> [FriendRequest] {
        let rows: [FriendRequestRow] = try await mapped {
            try await client.rpc("social_friend_requests").execute().value
        }
        return rows.map(\.request)
    }

    func friends() async throws -> [Friend] {
        let rows: [FriendRow] = try await mapped {
            try await client.rpc("social_friends").execute().value
        }
        return rows.map(\.friend)
    }

    func friendRanking(period: LeaderboardPeriod, date: LocalDate) async throws -> [LeaderboardEntry] {
        let response: LeaderboardResponse = try await mapped {
            try await client.rpc(
                "social_friend_ranking",
                params: ["p_period": period.rawValue, "p_date": date.isoString]
            ).execute().value
        }
        return response.entries.map(\.entry).sorted { $0.rank < $1.rank }
    }

    func friendProfile(_ publicID: UUID, date: LocalDate) async throws -> FriendProfileDetails {
        let row: FriendProfileRow = try await mapped {
            try await client.rpc(
                "social_friend_profile",
                params: FriendProfileParams(publicID: publicID, date: date.isoString)
            ).execute().value
        }
        return row.details
    }

    // MARK: Gruppen

    /// Gruppe, Privatsphäre und Einladungen in einer Transaktion. Fehlt die neue Fassung auf dem Server (vor Migration
    /// 20261019100100), wird nur dann die alte verwendet, wenn sie genau dasselbe ergibt (Code-Gruppe ohne
    /// Einladungen); sonst meldet die App „noch nicht eingerichtet“.
    func createGroup(_ draft: GroupDraft, timeZone: String) async throws -> GroupSummary {
        let params = CreateGroupParams(
            name: draft.name,
            description: draft.description,
            kind: draft.kind.rawValue,
            dailyGoal: draft.dailyGoal,
            timeZone: timeZone,
            privacy: draft.privacy.rawValue,
            inviteePublicIDs: draft.inviteePublicIDs
        )
        do {
            return try await summary("social_create_group", params)
        } catch SocialError.unavailable where draft.privacy == .code && draft.inviteePublicIDs.isEmpty {
            return try await summary("social_create_group", LegacyCreateGroupParams(
                name: draft.name,
                description: draft.description,
                kind: draft.kind.rawValue,
                dailyGoal: draft.dailyGoal,
                timeZone: timeZone
            ))
        }
    }

    func updateGroup(_ groupID: UUID, name: String, description: String, kind: GroupKind) async throws -> GroupSummary {
        try await summary("social_update_group", UpdateGroupParams(
            groupID: groupID,
            name: name,
            description: description,
            kind: kind.rawValue
        ))
    }

    func setGroupGoal(_ groupID: UUID, dailyGoal: Int) async throws -> GroupSummary {
        try await summary("social_set_group_goal", GroupGoalParams(groupID: groupID, dailyGoal: dailyGoal))
    }

    func myGroups() async throws -> [GroupSummary] {
        let rows: [GroupSummaryRow] = try await mapped {
            try await client.rpc("social_my_groups").execute().value
        }
        return rows.map(\.summary)
    }

    func group(_ groupID: UUID) async throws -> GroupSummary {
        try await summary("social_group", GroupIDParams(groupID: groupID))
    }

    func groupRanking(_ groupID: UUID, period: LeaderboardPeriod) async throws -> GroupRanking {
        let response: GroupRankingResponse = try await mapped {
            try await client.rpc(
                "social_group_ranking",
                params: GroupRankingParams(groupID: groupID, period: period.rawValue)
            ).execute().value
        }
        return response.ranking
    }

    func groupDays(_ groupID: UUID, count: Int) async throws -> [GroupDay] {
        let rows: [GroupDayRow] = try await mapped {
            try await client.rpc(
                "social_group_days",
                params: GroupDaysParams(groupID: groupID, days: min(max(count, 1), 60))
            ).execute().value
        }
        return rows.map(\.groupDay)
    }

    func regenerateInviteCode(_ groupID: UUID) async throws -> GroupSummary {
        try await summary("social_regenerate_invite_code", GroupIDParams(groupID: groupID))
    }

    func joinGroup(inviteCode: String) async throws -> GroupSummary {
        try await summary("social_join_group", ["p_invite_code": inviteCode])
    }

    func leaveGroup(_ groupID: UUID) async throws {
        try await mapped {
            try await client.rpc("social_leave_group", params: GroupIDParams(groupID: groupID)).execute()
        }
    }

    func removeMember(_ publicID: UUID, from groupID: UUID) async throws {
        try await mapped {
            try await client.rpc(
                "social_remove_group_member",
                params: GroupMemberParams(groupID: groupID, publicID: publicID)
            ).execute()
        }
    }

    func deleteGroup(_ groupID: UUID) async throws {
        try await mapped {
            try await client.rpc("social_delete_group", params: GroupIDParams(groupID: groupID)).execute()
        }
    }

    func invite(_ publicID: UUID, to groupID: UUID) async throws -> GroupInviteOutcome {
        let row: GroupInviteOutcomeRow = try await mapped {
            try await client.rpc(
                "social_invite_to_group",
                params: GroupMemberParams(groupID: groupID, publicID: publicID)
            ).execute().value
        }
        return GroupInviteOutcome(rawValue: row.status) ?? .invited
    }

    func groupInvitations() async throws -> [GroupInvitation] {
        let rows: [GroupInvitationRow] = try await mapped {
            try await client.rpc("social_group_invitations").execute().value
        }
        return rows.map(\.invitation)
    }

    func outgoingInvitations(for groupID: UUID) async throws -> [OutgoingGroupInvitation] {
        let rows: [OutgoingInvitationRow] = try await mapped {
            try await client.rpc("social_group_outgoing_invitations", params: GroupIDParams(groupID: groupID)).execute().value
        }
        return rows.map(\.invitation)
    }

    func respondToInvitation(_ invitationID: UUID, accept: Bool) async throws -> GroupSummary? {
        let row: InvitationResponseRow = try await mapped {
            try await client.rpc(
                "social_respond_group_invitation",
                params: RespondParams(idKey: .invitation, id: invitationID, accept: accept)
            ).execute().value
        }
        return row.group?.summary
    }

    func cancelInvitation(_ invitationID: UUID) async throws {
        try await mapped {
            try await client.rpc("social_cancel_group_invitation", params: ["p_invitation_id": invitationID]).execute()
        }
    }

    // MARK: Gruppen (Erweiterungen)

    func updateGroupDetails(
        _ groupID: UUID,
        name: String,
        description: String,
        kind: GroupKind,
        privacy: GroupPrivacy
    ) async throws -> GroupSummary {
        try await summary("social_update_group_details", UpdateGroupDetailsParams(
            groupID: groupID,
            name: name,
            description: description,
            kind: kind.rawValue,
            privacy: privacy.rawValue
        ))
    }

    func setGroupImage(_ groupID: UUID, path: String?) async throws -> GroupSummary {
        try await summary("social_set_group_image", GroupImageParams(groupID: groupID, path: path))
    }

    // MARK: Schutz

    func block(_ publicID: UUID) async throws {
        try await mapped {
            try await client.rpc("social_block_user", params: PublicIDParams(publicID: publicID)).execute()
        }
    }

    func unblock(_ publicID: UUID) async throws {
        try await mapped {
            try await client.rpc("social_unblock_user", params: PublicIDParams(publicID: publicID)).execute()
        }
    }

    func blockedUsers() async throws -> [SocialProfile] {
        let rows: [SocialProfileRow] = try await mapped {
            try await client.rpc("social_blocked_users").execute().value
        }
        return rows.map(\.profile)
    }

    func report(_ target: ReportTarget, reason: ReportReason, details: String?) async throws {
        let trimmed = details?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await mapped {
            try await client.rpc("social_report", params: ReportParams(
                target: target,
                reason: reason.rawValue,
                details: trimmed?.isEmpty == false ? trimmed : nil
            )).execute()
        }
    }

    // MARK: Spitznamen und Gruppenkalender

    /// Leere Eingaben entfernen den Spitznamen; Normalisierung und Prüfung wie auf dem Server (`NicknameRules`).
    @discardableResult
    func setFriendNickname(publicID: UUID, nickname: String?) async throws -> SocialProfile {
        let value = nickname.flatMap(NicknameRules.storedValue)
        if let value, NicknameRules.violation(for: value) != nil {
            throw SocialError.invalidNickname
        }
        let row: SocialProfileRow = try await mapped {
            try await client.rpc("social_set_friend_nickname", params: NicknameParams(publicID: publicID, nickname: value)).execute().value
        }
        return row.profile
    }

    /// Zeiträume über `GroupCalendarRules.maximumDays` lehnt schon die App ab (der Server antwortet `invalid_date`).
    func groupCalendar(groupID: UUID, from: LocalDate, to: LocalDate) async throws -> GroupCalendar {
        guard from <= to, Self.dayCount(from: from, to: to) <= GroupCalendarRules.maximumDays else {
            throw SocialError.invalidInput
        }
        let response: GroupCalendarResponse = try await mapped {
            try await client.rpc(
                "social_group_calendar",
                params: GroupCalendarParams(groupID: groupID, firstDay: from.isoString, lastDay: to.isoString)
            ).execute().value
        }
        return response.calendar
    }

    /// Anzahl der Kalendertage von `from` bis einschließlich `to` (unabhängig von Zeitzonen).
    private static func dayCount(from: LocalDate, to: LocalDate) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: from.year, month: from.month, day: from.day))!
        let end = calendar.date(from: DateComponents(year: to.year, month: to.month, day: to.day))!
        return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }

    // MARK: Hilfen

    private func summary(_ function: String, _ params: some Encodable & Sendable) async throws -> GroupSummary {
        let row: GroupSummaryRow = try await mapped {
            try await client.rpc(function, params: params).execute().value
        }
        return row.summary
    }

    @discardableResult
    private func mapped<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            if BackendFailure.isCancellation(error) { throw CancellationError() }
            throw BackendErrorMapping.socialError(error)
        }
    }
}

// MARK: - Parameter

private struct PublicIDParams: Encodable {
    let publicID: UUID

    enum CodingKeys: String, CodingKey {
        case publicID = "p_public_id"
    }
}

private struct RespondParams: Encodable {
    enum IDKey {
        case request, invitation
    }

    let idKey: IDKey
    let id: UUID
    let accept: Bool

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(id, forKey: Key(idKey == .request ? "p_request_id" : "p_invitation_id"))
        try container.encode(accept, forKey: Key("p_accept"))
    }
}

private struct FriendProfileParams: Encodable {
    let publicID: UUID
    let date: String

    enum CodingKeys: String, CodingKey {
        case publicID = "p_public_id"
        case date = "p_date"
    }
}

private struct CreateGroupParams: Encodable {
    let name: String
    let description: String
    let kind: String
    let dailyGoal: Int
    let timeZone: String
    let privacy: String
    let inviteePublicIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case name = "p_name"
        case description = "p_description"
        case kind = "p_kind"
        case dailyGoal = "p_daily_goal"
        case timeZone = "p_time_zone"
        case privacy = "p_privacy"
        case inviteePublicIDs = "p_invitee_public_ids"
    }
}

/// Fassung aus Migration 20261018100000 (ohne Privatsphäre und Einladungen).
private struct LegacyCreateGroupParams: Encodable {
    let name: String
    let description: String
    let kind: String
    let dailyGoal: Int
    let timeZone: String

    enum CodingKeys: String, CodingKey {
        case name = "p_name"
        case description = "p_description"
        case kind = "p_kind"
        case dailyGoal = "p_daily_goal"
        case timeZone = "p_time_zone"
    }
}

private struct UpdateGroupDetailsParams: Encodable {
    let groupID: UUID
    let name: String
    let description: String
    let kind: String
    let privacy: String

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
        case name = "p_name"
        case description = "p_description"
        case kind = "p_kind"
        case privacy = "p_privacy"
    }
}

private struct GroupImageParams: Encodable {
    let groupID: UUID
    let path: String?

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
        case path = "p_path"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupID, forKey: .groupID)
        // `null` entfernt das Bild; der Parameter hat keinen Standardwert und muss deshalb immer gesendet werden.
        try container.encode(path, forKey: .path)
    }
}

private struct ReportParams: Encodable {
    let target: ReportTarget
    let reason: String
    let details: String?

    enum CodingKeys: String, CodingKey {
        case targetType = "p_target_type"
        case targetID = "p_target_id"
        case reason = "p_reason"
        case details = "p_details"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch target {
        case .user(let publicID):
            try container.encode("user", forKey: .targetType)
            try container.encode(publicID, forKey: .targetID)
        case .message(let id):
            try container.encode("message", forKey: .targetType)
            try container.encode(id, forKey: .targetID)
        case .group(let id):
            try container.encode("group", forKey: .targetType)
            try container.encode(id, forKey: .targetID)
        }
        try container.encode(reason, forKey: .reason)
        try container.encodeIfPresent(details, forKey: .details)
    }
}

private struct UpdateGroupParams: Encodable {
    let groupID: UUID
    let name: String
    let description: String
    let kind: String

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
        case name = "p_name"
        case description = "p_description"
        case kind = "p_kind"
    }
}

private struct GroupGoalParams: Encodable {
    let groupID: UUID
    let dailyGoal: Int

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
        case dailyGoal = "p_daily_goal"
    }
}

private struct GroupIDParams: Encodable {
    let groupID: UUID

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
    }
}

private struct GroupRankingParams: Encodable {
    let groupID: UUID
    let period: String

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
        case period = "p_period"
    }
}

private struct GroupDaysParams: Encodable {
    let groupID: UUID
    let days: Int

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
        case days = "p_days"
    }
}

private struct GroupMemberParams: Encodable {
    let groupID: UUID
    let publicID: UUID

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
        case publicID = "p_public_id"
    }
}

private struct NicknameParams: Encodable {
    let publicID: UUID
    let nickname: String?

    enum CodingKeys: String, CodingKey {
        case publicID = "p_public_id"
        case nickname = "p_nickname"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(publicID, forKey: .publicID)
        // `null` entfernt den Spitznamen; der Parameter hat keinen Standardwert und muss immer gesendet werden.
        try container.encode(nickname, forKey: .nickname)
    }
}

private struct GroupCalendarParams: Encodable {
    let groupID: UUID
    let firstDay: String
    let lastDay: String

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
        case firstDay = "p_first_day"
        case lastDay = "p_last_day"
    }
}
