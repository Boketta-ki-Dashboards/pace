import DesignSystem
import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import SwiftUI
import Testing

/// Social-Hauptseite und ihre Unterseiten (Referenzbilder 1–4 und 9), jeweils mit Kopfzeile.
@MainActor
@Suite(.snapshotsEnabled)
struct SocialSnapshotTests {
    private let languages: [AppLanguage] = [.german, .english, .russian]

    private func page(_ content: some View) -> some View {
        content
            .padding(.horizontal, PaceSpacing.m)
            .padding(.vertical, PaceSpacing.m)
    }

    @Test func socialAndGroup() async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        try Snapshot.render(page(SocialContent(viewModel: dashboard.social)), name: "social-dashboard")
        let group = try #require(dashboard.social.groups.first)
        let detail = try #require(dashboard.social.detail(for: group))
        await detail.load()
        try Snapshot.render(page(GroupDetailContent(viewModel: detail)), name: "group")
    }

    @Test func socialMain() async throws {
        let social = await SocialSnapshotData.social()
        try Snapshot.render(page(SocialContent(viewModel: social)), name: "social", languages: languages)
    }

    @Test func addFriend() async throws {
        let social = await SocialSnapshotData.social()
        let search = try #require(social.friendSearch(debounce: .seconds(60)))
        search.query = "leo"
        await search.searchNow()
        try Snapshot.render(page(AddFriendContent(model: search, social: social)), name: "add-friend", languages: languages)
    }

    @Test func friendRequests() async throws {
        let social = await SocialSnapshotData.social()
        try Snapshot.render(page(FriendRequestsContent(viewModel: social)), name: "friend-requests", languages: languages)
    }

    @Test func createGroup() async throws {
        let social = await SocialSnapshotData.social(media: MediaRepositoryStub())
        let form = social.createGroupForm()
        form.name = "Abendrunde"
        form.description = "Gemeinsam jeden Tag ein Stück weiter."
        for friend in social.friends.prefix(3) {
            form.toggleInvitee(friend.profile.publicID)
        }
        try Snapshot.render(page(CreateGroupContent(model: form, social: social)), name: "create-group", languages: languages)
    }

    @Test func groupPages() async throws {
        let social = await SocialSnapshotData.social()
        let detail = try #require(social.detail(groupID: SocialSnapshotData.groupID))
        await detail.load()
        try Snapshot.render(page(GroupDetailContent(viewModel: detail)), name: "group-detail", languages: languages)
        try Snapshot.render(page(GroupMembersContent(viewModel: detail)), name: "group-members")
        try Snapshot.render(
            page(GroupSettingsContent(viewModel: detail, form: .constant(GroupSettingsForm(group: detail.group)))),
            name: "group-settings"
        )
    }

    @Test func userProfile() async throws {
        let social = await SocialSnapshotData.social()
        let profile = try #require(social.userProfile(for: SocialSnapshotData.leon))
        await profile.load()
        try Snapshot.render(page(UserProfileContent(model: profile, social: social)), name: "user-profile", languages: languages)
    }

    /// Spitzname: Profil mit eigenem Spitznamen (Anzeigename darunter) und die Eingabe zum Ändern.
    @Test func nickname() async throws {
        let social = await SocialSnapshotData.social()
        let profile = try #require(social.userProfile(for: SocialSnapshotData.leon))
        await profile.load()
        #expect(await profile.saveNickname("Laufpartner Leon"))
        try Snapshot.render(page(UserProfileContent(model: profile, social: social)), name: "user-profile-nickname", languages: languages)
        // Mit Navigationsleiste (Abbrechen/Speichern) – deshalb im Fenster gerendert.
        try await Snapshot.renderInWindow(NicknameEditSheet(model: profile), name: "nickname-edit")
    }

    /// Gruppenkalender mit gesicherten und offenen Tagen, Tag ohne Daten, Zukunft und Tagesrangliste.
    @Test func groupCalendar() async throws {
        let repository = SocialRepositoryStub { $0.calendars[SocialSnapshotData.groupID] = SocialSnapshotData.calendar() }
        let calendar = GroupCalendarViewModel(
            groupID: SocialSnapshotData.groupID,
            groupName: "Smoking red",
            repository: repository,
            calendar: Fixtures.activityCalendar,
            now: { Fixtures.date(2026, 10, 16, 18) }
        )
        await calendar.load()
        calendar.select(Fixtures.day(2026, 10, 14))
        try Snapshot.render(page(GroupCalendarContent(viewModel: calendar)), name: "group-calendar", languages: languages)
    }

    @Test func moreSocialPages() async throws {
        let social = await SocialSnapshotData.social()
        try Snapshot.render(page(GroupsContent(viewModel: social, inviteCode: .constant(""))), name: "social-groups")
        let ranking = social.friendsRanking()
        try Snapshot.render(page(FriendsRankingContent(model: ranking)), name: "friends-ranking")
        let settings = social.settings()
        await settings.load()
        try Snapshot.render(page(SocialSettingsContent(model: settings, social: social)), name: "social-settings")
        try Snapshot.render(page(ShareProfileContent(model: social.shareProfile(SocialSnapshotData.leon))), name: "share-profile")
        let report = social.reportForm(.user(SocialSnapshotData.leon))
        report.reason = .spam
        try Snapshot.render(page(ReportContent(model: report, social: social)), name: "report")
    }

    @Test func unavailable() throws {
        let social = SocialViewModel(repository: nil, ownUsername: { "niklas" })
        try Snapshot.render(page(SocialContent(viewModel: social)), name: "social-unavailable")
    }
}

/// Beispieldaten im Stil der Referenzbilder (nur für Bilder).
private enum SocialSnapshotData {
    /// Gruppenkalender Oktober 2026 (6 Mitglieder, Ziel 8.000, benötigt 2): Werte nur für Bilder.
    static func calendar() -> GroupCalendar {
        let members = [me, leon, marie, gotscha, flavio, leo]
        let days: [GroupCalendarDay] = (1...16).map { dayNumber in
            let day = Fixtures.day(2026, 10, dayNumber)
            let hasData = dayNumber != 15
            let steps = members.enumerated().map { index, _ in hasData ? (dayNumber * 1_373 + index * 2_711) % 15_000 : 0 }
            let order = steps.indices.sorted { steps[$0] == steps[$1] ? $0 < $1 : steps[$0] > steps[$1] }
            let ranking = hasData ? order.enumerated().map { rank, index in
                GroupCalendarEntry(
                    rank: rank + 1,
                    profile: members[index],
                    competitionSteps: steps[index],
                    reached: steps[index] >= 8_000,
                    isCurrentUser: index == 0
                )
            } : []
            let reached = ranking.filter(\.reached).count
            return GroupCalendarDay(
                day: day,
                dailyGoal: 8_000,
                memberCount: members.count,
                requiredCount: 2,
                reachedCount: reached,
                secured: reached >= 2,
                hasData: hasData,
                isToday: dayNumber == 16,
                ranking: ranking
            )
        }
        return GroupCalendar(
            groupID: groupID,
            timeZone: "Europe/Berlin",
            groupToday: Fixtures.day(2026, 10, 16),
            firstGroupDay: Fixtures.day(2026, 10, 1),
            days: days
        )
    }

    static let groupID = UUID(uuidString: "60000000-0000-4000-8000-000000000001")!

    static func profile(_ index: Int, _ name: String, _ username: String) -> SocialProfile {
        SocialProfile(
            publicID: UUID(uuidString: String(format: "70000000-0000-4000-8000-%012d", index))!,
            username: username,
            displayName: name
        )
    }

    static let me = profile(1, "Niklas", "niklas")
    static let leon = profile(2, "Leon Fischer", "leon_fischer")
    static let marie = profile(3, "Marie", "marie")
    static let gotscha = profile(4, "Gotscha", "gotscha")
    static let flavio = profile(5, "Flavio", "flavio")
    static let leona = profile(6, "Leona Weber", "leona_w")
    static let leo = profile(7, "Leo Müller", "leo_mueller")
    static let leonie = profile(8, "Leonie Braun", "leonie_b")
    static let clara = profile(9, "Clara Hoffmann", "clara_h")
    static let jonas = profile(10, "Jonas Becker", "jonas_b")
    static let emilia = profile(11, "Emilia Wolf", "emilia_w")
    static let tim = profile(12, "Tim Schneider", "tim_s")

    @MainActor
    static func social(media: MediaRepositoryStub? = nil) async -> SocialViewModel {
        let repository = SocialRepositoryStub { state in
            let friends = [leon, marie, gotscha, flavio, leo]
            state.friends = friends.map { Friend(profile: $0, friendsSince: Fixtures.date(2026, 3, 14)) }
            state.ranking = [
                entry(1, leon, 12_480),
                entry(2, marie, 10_920),
                entry(3, gotscha, 9_610),
                LeaderboardEntry(rank: 4, publicUserID: me.publicID, username: me.username, displayName: me.displayName, competitionSteps: 8_432, isCurrentUser: true),
                entry(5, flavio, 7_280),
                entry(6, leo, 4_105),
            ]
            state.requests = [
                FriendRequest(id: UUID(), direction: .incoming, profile: clara, createdAt: .distantPast),
                FriendRequest(id: UUID(), direction: .incoming, profile: jonas, createdAt: .distantPast),
                FriendRequest(id: UUID(), direction: .incoming, profile: emilia, createdAt: .distantPast),
                FriendRequest(id: UUID(), direction: .outgoing, profile: leona, createdAt: .distantPast),
                FriendRequest(id: UUID(), direction: .outgoing, profile: tim, createdAt: .distantPast),
            ]
            state.searchableProfiles = [leon, leona, leo, leonie]
            state.relationships[leo.publicID] = .friend
            state.relationships[leona.publicID] = .outgoingRequest
            state.groups = [
                SocialRepositoryStub.group(
                    id: groupID, name: "Smoking red", description: "Jeden Abend eine Runde.", kind: .friends,
                    memberCount: 12, currentStreak: 12, reached: 4, privacy: .code
                ),
                SocialRepositoryStub.group(name: "Klassengruppe", kind: .schoolClass, role: .member, memberCount: 24, currentStreak: 3, reached: 5),
            ]
            state.groupRankings[groupID] = GroupRanking(
                totalParticipants: 12,
                groupToday: Fixtures.day(2026, 10, 16),
                dailyGoal: 8_000,
                entries: [
                    groupEntry(1, leon, 12_480, reached: true),
                    groupEntry(2, marie, 10_920, reached: true),
                    groupEntry(3, gotscha, 9_610, reached: true),
                    GroupRankingEntry(rank: 4, profile: me, competitionSteps: 8_432, isCurrentUser: true, role: .owner, reachedGoalToday: true),
                    groupEntry(5, flavio, 7_280, reached: false),
                ]
            )
            state.outgoingInvitations[groupID] = [OutgoingGroupInvitation(id: UUID(), profile: leo, createdAt: .distantPast)]
            state.invitations = [GroupInvitation(
                id: UUID(), groupID: UUID(), groupName: "Sonntagsrunde", groupKind: .friends, memberCount: 4,
                inviterUsername: "marie", inviterDisplayName: "Marie", createdAt: .distantPast
            )]
            state.blocked = [profile(13, "Max Muster", "max_muster")]
        }
        let social = SocialViewModel(
            repository: repository,
            media: media,
            ownUsername: { "niklas" },
            calendar: Fixtures.activityCalendar,
            now: { Fixtures.date(2026, 10, 16, 18, 30) }
        )
        await social.load()
        return social
    }

    private static func entry(_ rank: Int, _ profile: SocialProfile, _ steps: Int) -> LeaderboardEntry {
        LeaderboardEntry(
            rank: rank, publicUserID: profile.publicID, username: profile.username, displayName: profile.displayName,
            competitionSteps: steps, isCurrentUser: false
        )
    }

    private static func groupEntry(_ rank: Int, _ profile: SocialProfile, _ steps: Int, reached: Bool) -> GroupRankingEntry {
        GroupRankingEntry(rank: rank, profile: profile, competitionSteps: steps, isCurrentUser: false, role: .member, reachedGoalToday: reached)
    }
}
