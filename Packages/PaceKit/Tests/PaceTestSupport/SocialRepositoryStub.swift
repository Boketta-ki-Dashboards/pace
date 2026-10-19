import Foundation
import PaceCore

/// Konfigurierbarer Test-Double für `SocialRepository`. Hält Freunde, Anfragen und Gruppen im Speicher und zeichnet
/// Aufrufe auf. Serverregeln (Limits, Streak) werden nicht nachgebaut – dafür gibt es die pgTAP-Tests.
public final class SocialRepositoryStub: SocialRepository, Sendable {
    public struct State: Sendable {
        public var profiles: [String: SocialProfile] = [:]
        public var relationships: [UUID: SocialRelationship] = [:]
        public var friends: [Friend] = []
        public var requests: [FriendRequest] = []
        public var ranking: [LeaderboardEntry] = []
        /// Wochenranking der Freunde; ohne Eintrag gilt `ranking`.
        public var weeklyRanking: [LeaderboardEntry]?
        /// Zeiträume, nach denen das Freundesranking abgefragt wurde.
        public var friendRankingPeriods: [LeaderboardPeriod] = []
        public var groups: [GroupSummary] = []
        public var groupRankings: [UUID: GroupRanking] = [:]
        /// Wochenrankings; ohne Eintrag gilt `groupRankings`.
        public var weeklyGroupRankings: [UUID: GroupRanking] = [:]
        public var groupDays: [UUID: [GroupDay]] = [:]
        public var invitations: [GroupInvitation] = []
        public var outgoingInvitations: [UUID: [OutgoingGroupInvitation]] = [:]
        public var friendRequestOutcome: FriendRequestOutcome = .requested
        /// Treffer der Präfix-Suche (nach Benutzername gefiltert).
        public var searchableProfiles: [SocialProfile] = []
        public var blocked: [SocialProfile] = []
        public var reports: [(ReportTarget, ReportReason, String?)] = []
        /// Fehler für alle Aufrufe.
        public var error: SocialError?
        /// Fehler nur für Schreibaktionen.
        public var actionError: SocialError?
        public var calls: [String] = []
    }

    public let state: Locked<State>
    /// Hält `myGroups`, `searchProfiles` bzw. `groupRanking:daily`/`groupRanking:weekly` an. Die Daten werden schon beim Aufruf
    /// gelesen – wie bei einer Serverantwort, die unterwegs ist.
    public let gate = CallGate()

    public init(configure: (inout State) -> Void = { _ in }) {
        var state = State()
        configure(&state)
        self.state = Locked(state)
    }

    private func read<T>(_ name: String, _ body: (State) -> T) throws -> T {
        try state.withLock { state in
            state.calls.append(name)
            if let error = state.error { throw error }
            return body(state)
        }
    }

    private func write<T>(_ name: String, _ body: (inout State) throws -> T) throws -> T {
        try state.withLock { state in
            state.calls.append(name)
            if let error = state.error ?? state.actionError { throw error }
            return try body(&state)
        }
    }

    public func findProfile(username: String) async throws -> ProfileSearchResult? {
        try read("findProfile") { state in
            state.profiles[username.lowercased()].map {
                ProfileSearchResult(profile: $0, relationship: state.relationships[$0.publicID] ?? .none, requestID: nil)
            }
        }
    }

    public func sendFriendRequest(to publicID: UUID) async throws -> FriendRequestOutcome {
        try write("sendFriendRequest") { state in
            state.relationships[publicID] = state.friendRequestOutcome == .accepted ? .friend : .outgoingRequest
            return state.friendRequestOutcome
        }
    }

    public func respondToFriendRequest(_ requestID: UUID, accept: Bool) async throws {
        try write("respondToFriendRequest") { state in
            guard let index = state.requests.firstIndex(where: { $0.id == requestID }) else { throw SocialError.notFound }
            let request = state.requests.remove(at: index)
            if accept {
                state.friends.append(Friend(profile: request.profile, friendsSince: Date(timeIntervalSince1970: 0)))
            }
        }
    }

    public func cancelFriendRequest(_ requestID: UUID) async throws {
        try write("cancelFriendRequest") { state in
            state.requests.removeAll { $0.id == requestID }
        }
    }

    public func removeFriend(_ publicID: UUID) async throws {
        try write("removeFriend") { state in
            guard state.friends.contains(where: { $0.profile.publicID == publicID }) else { throw SocialError.notFound }
            state.friends.removeAll { $0.profile.publicID == publicID }
        }
    }

    public func friendRequests() async throws -> [FriendRequest] {
        try read("friendRequests") { $0.requests }
    }

    public func friends() async throws -> [Friend] {
        try read("friends") { $0.friends }
    }

    public func friendRanking(period: LeaderboardPeriod, date: LocalDate) async throws -> [LeaderboardEntry] {
        state.withLock { $0.friendRankingPeriods.append(period) }
        return try read("friendRanking") { state in
            period == .weekly ? (state.weeklyRanking ?? state.ranking) : state.ranking
        }
    }

    public func friendProfile(_ publicID: UUID, date: LocalDate) async throws -> FriendProfileDetails {
        let friend = try read("friendProfile") { state in state.friends.first { $0.profile.publicID == publicID } }
        guard let friend else { throw SocialError.notFound }
        return FriendProfileDetails(profile: friend.profile, friendsSince: friend.friendsSince, stepsToday: 4_200, stepsWeek: 30_100)
    }

    public func createGroup(_ draft: GroupDraft, timeZone: String) async throws -> GroupSummary {
        try write("createGroup") { state in
            let group = Self.group(name: draft.name, kind: draft.kind, goal: draft.dailyGoal, timeZone: timeZone, privacy: draft.privacy)
            state.groups.append(group)
            for invitee in draft.inviteePublicIDs {
                guard let friend = state.friends.first(where: { $0.profile.publicID == invitee }) else { continue }
                state.outgoingInvitations[group.id, default: []].append(
                    OutgoingGroupInvitation(id: UUID(), profile: friend.profile, createdAt: Date(timeIntervalSince1970: 0))
                )
            }
            return group
        }
    }

    public func updateGroup(_ groupID: UUID, name: String, description: String, kind: GroupKind) async throws -> GroupSummary {
        try write("updateGroup") { state in
            guard let index = state.groups.firstIndex(where: { $0.id == groupID }) else { throw SocialError.notFound }
            let old = state.groups[index]
            let updated = Self.group(id: groupID, name: name, description: description, kind: kind, goal: old.dailyGoal, timeZone: old.timeZone)
            state.groups[index] = updated
            return updated
        }
    }

    public func setGroupGoal(_ groupID: UUID, dailyGoal: Int) async throws -> GroupSummary {
        try write("setGroupGoal") { state in
            guard let group = state.groups.first(where: { $0.id == groupID }) else { throw SocialError.notFound }
            return group
        }
    }

    public func myGroups() async throws -> [GroupSummary] {
        let groups = try read("myGroups") { $0.groups }
        await gate.pass("myGroups")
        return groups
    }

    public func group(_ groupID: UUID) async throws -> GroupSummary {
        let group = try read("group") { state in state.groups.first { $0.id == groupID } }
        guard let group else { throw SocialError.notFound }
        return group
    }

    public func groupRanking(_ groupID: UUID, period: LeaderboardPeriod) async throws -> GroupRanking {
        let name = "groupRanking:\(period.rawValue)"
        let ranking = try read(name) { state in
            (period == .weekly ? state.weeklyGroupRankings[groupID] : nil)
                ?? state.groupRankings[groupID]
                ?? GroupRanking(totalParticipants: 0, groupToday: LocalDate(year: 2026, month: 10, day: 16), dailyGoal: 10_000, entries: [])
        }
        await gate.pass(name)
        return ranking
    }

    public func groupDays(_ groupID: UUID, count: Int) async throws -> [GroupDay] {
        try read("groupDays") { $0.groupDays[groupID] ?? [] }
    }

    public func regenerateInviteCode(_ groupID: UUID) async throws -> GroupSummary {
        try write("regenerateInviteCode") { state in
            guard let group = state.groups.first(where: { $0.id == groupID }) else { throw SocialError.notFound }
            return group
        }
    }

    public func joinGroup(inviteCode: String) async throws -> GroupSummary {
        try write("joinGroup:\(inviteCode)") { state in
            guard let group = state.groups.first(where: { $0.inviteCode == inviteCode }) else { throw SocialError.invalidInviteCode }
            return group
        }
    }

    public func leaveGroup(_ groupID: UUID) async throws {
        try write("leaveGroup") { state in
            state.groups.removeAll { $0.id == groupID }
        }
    }

    public func removeMember(_ publicID: UUID, from groupID: UUID) async throws {
        try write("removeMember") { state in
            guard let ranking = state.groupRankings[groupID] else { return }
            let entries = ranking.entries.filter { $0.profile.publicID != publicID }
            state.groupRankings[groupID] = GroupRanking(
                totalParticipants: entries.count, groupToday: ranking.groupToday, dailyGoal: ranking.dailyGoal, entries: entries
            )
        }
    }

    public func deleteGroup(_ groupID: UUID) async throws {
        try write("deleteGroup") { state in
            state.groups.removeAll { $0.id == groupID }
        }
    }

    public func invite(_ publicID: UUID, to groupID: UUID) async throws -> GroupInviteOutcome {
        try write("invite") { state in
            let profile = state.friends.first { $0.profile.publicID == publicID }?.profile
                ?? SocialProfile(publicID: publicID, username: "x", displayName: "X")
            state.outgoingInvitations[groupID, default: []].append(
                OutgoingGroupInvitation(id: UUID(), profile: profile, createdAt: Date(timeIntervalSince1970: 0))
            )
            return .invited
        }
    }

    public func groupInvitations() async throws -> [GroupInvitation] {
        try read("groupInvitations") { $0.invitations }
    }

    public func outgoingInvitations(for groupID: UUID) async throws -> [OutgoingGroupInvitation] {
        try read("outgoingInvitations") { $0.outgoingInvitations[groupID] ?? [] }
    }

    public func respondToInvitation(_ invitationID: UUID, accept: Bool) async throws -> GroupSummary? {
        try write("respondToInvitation") { state in
            state.invitations.removeAll { $0.id == invitationID }
            return nil
        }
    }

    public func cancelInvitation(_ invitationID: UUID) async throws {
        try write("cancelInvitation") { state in
            for key in state.outgoingInvitations.keys {
                state.outgoingInvitations[key]?.removeAll { $0.id == invitationID }
            }
        }
    }

    public func searchProfiles(query: String) async throws -> [ProfileSearchResult] {
        let results = try read("searchProfiles:\(query)") { state in
            let lowered = query.lowercased()
            let blockedIDs = Set(state.blocked.map(\.publicID))
            return state.searchableProfiles
                .filter { $0.username.lowercased().hasPrefix(lowered) && !blockedIDs.contains($0.publicID) }
                .sorted { lhs, rhs in
                    let lhsExact = lhs.username.lowercased() == lowered, rhsExact = rhs.username.lowercased() == lowered
                    return lhsExact != rhsExact ? lhsExact : lhs.username < rhs.username
                }
                .prefix(20)
                .map { ProfileSearchResult(profile: $0, relationship: state.relationships[$0.publicID] ?? .none, requestID: nil) }
        }
        await gate.pass("searchProfiles")
        return results
    }

    public func publicProfile(_ publicID: UUID, date: LocalDate) async throws -> PublicProfile {
        let found = try read("publicProfile") { state -> PublicProfile? in
            let friend = state.friends.first { $0.profile.publicID == publicID }
            let known = friend?.profile
                ?? state.searchableProfiles.first { $0.publicID == publicID }
                ?? state.profiles.values.first { $0.publicID == publicID }
                ?? state.requests.first { $0.profile.publicID == publicID }?.profile
            guard let profile = known else { return nil }
            let isFriend = friend != nil
            // Offene Anfragen bestimmen die Beziehung wie auf dem Server.
            let request = state.requests.first { $0.profile.publicID == publicID }
            let requestRelationship: SocialRelationship? = request.map { $0.direction == .incoming ? .incomingRequest : .outgoingRequest }
            return PublicProfile(
                profile: profile,
                relationship: isFriend ? .friend : (requestRelationship ?? state.relationships[publicID] ?? .none),
                requestID: isFriend ? nil : request?.id,
                friendsSince: friend?.friendsSince,
                stepsToday: isFriend ? 4_200 : nil,
                stepsWeek: isFriend ? 30_100 : nil,
                isBlockedByMe: state.blocked.contains { $0.publicID == publicID }
            )
        }
        guard let found else { throw SocialError.notFound }
        return found
    }

    public func updateGroupDetails(_ groupID: UUID, name: String, description: String, kind: GroupKind, privacy: GroupPrivacy) async throws -> GroupSummary {
        try write("updateGroupDetails") { state in
            guard let index = state.groups.firstIndex(where: { $0.id == groupID }) else { throw SocialError.notFound }
            let old = state.groups[index]
            let updated = Self.group(
                id: groupID, name: name, description: description, kind: kind, role: old.role, memberCount: old.memberCount,
                goal: old.dailyGoal, timeZone: old.timeZone, currentStreak: old.currentStreak, reached: old.todayReachedCount,
                imagePath: old.imagePath, privacy: privacy
            )
            state.groups[index] = updated
            return updated
        }
    }

    public func setGroupImage(_ groupID: UUID, path: String?) async throws -> GroupSummary {
        try write("setGroupImage") { state in
            guard let index = state.groups.firstIndex(where: { $0.id == groupID }) else { throw SocialError.notFound }
            let old = state.groups[index]
            let updated = Self.group(
                id: groupID, name: old.name, description: old.description, kind: old.kind, role: old.role,
                memberCount: old.memberCount, goal: old.dailyGoal, timeZone: old.timeZone, currentStreak: old.currentStreak,
                reached: old.todayReachedCount, imagePath: path, privacy: old.privacy
            )
            state.groups[index] = updated
            return updated
        }
    }

    public func block(_ publicID: UUID) async throws {
        try write("block") { state in
            let profile = state.friends.first { $0.profile.publicID == publicID }?.profile
                ?? state.searchableProfiles.first { $0.publicID == publicID }
                ?? SocialProfile(publicID: publicID, username: "blockiert", displayName: "Blockiert")
            if !state.blocked.contains(where: { $0.publicID == publicID }) { state.blocked.append(profile) }
            state.friends.removeAll { $0.profile.publicID == publicID }
            state.requests.removeAll { $0.profile.publicID == publicID }
            state.relationships[publicID] = SocialRelationship.none
        }
    }

    public func unblock(_ publicID: UUID) async throws {
        try write("unblock") { state in
            state.blocked.removeAll { $0.publicID == publicID }
        }
    }

    public func blockedUsers() async throws -> [SocialProfile] {
        try read("blockedUsers") { $0.blocked }
    }

    public func report(_ target: ReportTarget, reason: ReportReason, details: String?) async throws {
        try write("report") { state in
            state.reports.append((target, reason, details))
        }
    }

    /// Beispielgruppe für Tests.
    public static func group(
        id: UUID = UUID(),
        name: String = "Klasse 8b",
        description: String = "",
        kind: GroupKind = .schoolClass,
        role: GroupRole = .owner,
        memberCount: Int = 6,
        goal: Int = 8_000,
        timeZone: String = "Europe/Berlin",
        inviteCode: String = "K7M2Q9XA",
        currentStreak: Int = 4,
        reached: Int = 1,
        imagePath: String? = nil,
        privacy: GroupPrivacy = .code
    ) -> GroupSummary {
        GroupSummary(
            id: id,
            name: name,
            description: description,
            kind: kind,
            role: role,
            memberCount: memberCount,
            dailyGoal: goal,
            nextDailyGoal: nil,
            timeZone: timeZone,
            groupToday: LocalDate(year: 2026, month: 10, day: 16),
            inviteCode: inviteCode,
            currentStreak: currentStreak,
            bestStreak: max(currentStreak, 9),
            todayReachedCount: reached,
            todayRequiredCount: GroupStreakRules.requiredMembers(forMemberCount: memberCount),
            todayComplete: reached >= GroupStreakRules.requiredMembers(forMemberCount: memberCount),
            createdAt: Date(timeIntervalSince1970: 0),
            imagePath: imagePath,
            privacy: privacy
        )
    }
}
