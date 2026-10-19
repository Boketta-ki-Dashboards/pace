@testable import ActivityFeature
import Foundation
@testable import HomeFeature
@testable import LeaderboardFeature
import PaceCore
import PaceTestSupport
@testable import SocialFeature

/// Beispieldaten für die Snapshot-Bilder (nur für Bilder, nie in der App).
@MainActor
enum SnapshotFixtures {
    static func makeDashboard() async throws -> (HomeDashboardViewModel, ProfileStore) {
        let profile = Fixtures.profile(displayName: "Niklas", regionalLeaderboardEnabled: true)
        let profiles = ProfileRepositoryStub { $0.profiles[profile.id] = profile }
        let store = ProfileStore(profile: profile, profiles: profiles, regions: RegionRepositoryStub(), cache: InMemoryProfileCache())
        try await store.loadHierarchyIfNeeded()

        let calendar = Fixtures.activityCalendar
        let today = Fixtures.day(2026, 10, 16)
        let week = [6_210, 8_904, 5_480, 6_020, 8_432]
        let health = HealthServiceStub { configuration in
            // Sechs Wochen Verlauf für die Statistik, die aktuelle Woche wie im Home-Mockup.
            for offset in -45 ... -7 {
                let day = calendar.adding(offset, to: today)
                let steps = 5_000 + Int((offset * 7_919).magnitude % 8_000)
                configuration.setSteps(steps, on: day)
                configuration.set(.walkingRunningDistance, Double(steps) * 0.72, on: day)
                configuration.set(.activeEnergy, Double(steps) * 0.0384, on: day)
            }
            for (offset, steps) in week.enumerated() {
                let day = calendar.adding(offset - 4, to: today)
                configuration.setSteps(steps, on: day)
                configuration.set(.walkingRunningDistance, Double(steps) * 0.72, on: day)
                configuration.set(.activeEnergy, Double(steps) * 0.0384, on: day)
            }
            configuration.setSteps(10_400, on: calendar.adding(-5, to: today))
            configuration.setSteps(11_900, on: calendar.adding(-6, to: today))
            configuration.set(.flightsClimbed, 7, on: today)
            configuration.set(.exerciseTime, 34, on: today)
            configuration.hourlyTotals[.competitionSteps] = [
                today: [7: 640, 8: 1_210, 9: 380, 12: 1_450, 13: 520, 16: 980, 17: 2_102, 18: 1_150],
                calendar.adding(-1, to: today): [7: 500, 8: 900, 12: 1_100, 17: 1_800, 18: 700, 19: 1_020],
            ]
        }
        let now: @Sendable () -> Date = { Fixtures.date(2026, 10, 16, 18, 30) }
        let activity = HomeViewModel(activityData: health, calendar: calendar, now: now)
        await activity.loadIfNeeded()

        let standings = RegionalStandingsViewModel(
            store: store,
            leaderboards: Self.leaderboards(),
            syncing: nil,
            calendar: calendar,
            now: { Fixtures.date(2026, 10, 16, 18) }
        )
        standings.neighborhoodRadii = [.municipality: 2, .district: 4]
        await standings.load()

        let social = SocialViewModel(
            repository: Self.socialRepository(),
            ownUsername: { "niklas" },
            calendar: calendar,
            now: now
        )
        await social.load()
        let streak = StepStreakTracker(
            history: ActivityHistoryStore(activityData: health, live: activity, calendar: calendar, now: now),
            goals: StepGoalSettings(store: InMemoryStepGoalStore(), calendar: calendar, now: now),
            recordStore: InMemoryStepStreakRecordStore(),
            calendar: calendar,
            now: now
        )
        let dashboard = HomeDashboardViewModel(
            activity: activity,
            standings: standings,
            settings: HomeSettings(store: InMemoryHomePreferencesStore()),
            streak: streak,
            social: social,
            activityData: health,
            store: store,
            calendar: calendar,
            formatter: ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: calendar),
            now: now
        )
        return (dashboard, store)
    }

    static func socialRepository() -> SocialRepositoryStub {
        func profile(_ index: Int, _ name: String) -> SocialProfile {
            SocialProfile(
                publicID: UUID(uuidString: String(format: "40000000-0000-4000-8000-%012d", index))!,
                username: name.lowercased(),
                displayName: name
            )
        }
        let mia = profile(1, "Mia"), jonas = profile(2, "Jonas"), lea = profile(3, "Lea")
        let me = LeaderboardEntry(
            rank: 2, publicUserID: profile(9, "Niklas").publicID, username: "niklas", displayName: "Niklas",
            competitionSteps: 8_432, isCurrentUser: true
        )
        return SocialRepositoryStub { state in
            state.friends = [mia, jonas, lea].map { Friend(profile: $0, friendsSince: .distantPast) }
            state.ranking = [
                LeaderboardEntry(rank: 1, publicUserID: mia.publicID, username: "mia", displayName: "Mia", competitionSteps: 10_204, isCurrentUser: false),
                me,
                LeaderboardEntry(rank: 3, publicUserID: jonas.publicID, username: "jonas", displayName: "Jonas", competitionSteps: 6_870, isCurrentUser: false),
                LeaderboardEntry(rank: 4, publicUserID: lea.publicID, username: "lea", displayName: "Lea", competitionSteps: 3_115, isCurrentUser: false),
            ]
            state.requests = [FriendRequest(id: UUID(), direction: .incoming, profile: profile(4, "Ben"), createdAt: .distantPast)]
            let classID = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!
            state.groups = [
                SocialRepositoryStub.group(
                    id: classID, name: "Klasse 8b", description: "Wer schafft die meisten Schritte bis zu den Ferien?",
                    kind: .schoolClass, memberCount: 24, currentStreak: 6, reached: 9
                ),
                SocialRepositoryStub.group(name: "Laufteam Büro", kind: .work, memberCount: 7, currentStreak: 2, reached: 1),
            ]
            state.groupRankings[classID] = GroupRanking(
                totalParticipants: 4,
                groupToday: Fixtures.day(2026, 10, 16),
                dailyGoal: 8_000,
                entries: [
                    GroupRankingEntry(rank: 1, profile: mia, competitionSteps: 10_204, isCurrentUser: false, role: .member, reachedGoalToday: true),
                    GroupRankingEntry(rank: 2, profile: profile(9, "Niklas"), competitionSteps: 8_432, isCurrentUser: true, role: .owner, reachedGoalToday: true),
                    GroupRankingEntry(rank: 3, profile: jonas, competitionSteps: 6_870, isCurrentUser: false, role: .member, reachedGoalToday: false),
                    GroupRankingEntry(rank: 4, profile: lea, competitionSteps: 3_115, isCurrentUser: false, role: .member, reachedGoalToday: false),
                ]
            )
            state.groupDays[classID] = (0..<14).map { offset in
                let day = Fixtures.activityCalendar.adding(-offset, to: Fixtures.day(2026, 10, 16))
                let reached = offset == 0 ? 9 : (offset == 7 ? 5 : 8 + offset % 4)
                return GroupDay(day: day, memberCount: 24, requiredCount: 8, reachedCount: reached, dailyGoal: 8_000, reached: reached >= 8, isToday: offset == 0)
            }
            state.invitations = [GroupInvitation(
                id: UUID(), groupID: UUID(), groupName: "Sonntagsrunde", groupKind: .friends, memberCount: 4,
                inviterUsername: "mia", inviterDisplayName: "Mia", createdAt: .distantPast
            )]
        }
    }

    static func leaderboards() -> LeaderboardRepositoryStub {
        let names = ["Leon", "Flavio", "Mia", "Jonas", "Emma", "Ben", "Lina", "Paul", "Lea", "Finn", "Leon", "Niklas", "Flavio"]
        func ranking(count: Int, me: Int, myRankSteps: Int) -> [LeaderboardEntry] {
            (1...count).map { rank in
                let steps = myRankSteps + (me - rank) * 140 + (rank == me - 1 ? 139 : 0)
                return LeaderboardEntry(
                    rank: rank,
                    publicUserID: UUID(uuidString: String(format: "30000000-0000-4000-8000-%012d", rank))!,
                    username: rank == me ? "niklas" : "nutzer\(rank)",
                    displayName: rank == me ? "Niklas" : names[(rank - 1) % names.count],
                    competitionSteps: max(steps, 0),
                    isCurrentUser: rank == me
                )
            }
        }
        return LeaderboardRepositoryStub {
            $0.rankings[Fixtures.pfungstadt.id] = ranking(count: 30, me: 12, myRankSteps: 8_432)
            $0.rankings[Fixtures.darmstadtDieburg.id] = ranking(count: 160, me: 148, myRankSteps: 8_432)
            $0.rankings[Fixtures.hessen.id] = ranking(count: 2_500, me: 2_410, myRankSteps: 8_432)
            $0.rankings[Fixtures.germany.id] = ranking(count: 18_600, me: 18_520, myRankSteps: 8_432)
        }
    }
}
