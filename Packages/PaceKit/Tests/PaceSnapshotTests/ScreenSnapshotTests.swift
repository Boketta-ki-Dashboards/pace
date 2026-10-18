@testable import ActivityFeature
import DesignSystem
import Foundation
@testable import HomeFeature
@testable import LeaderboardFeature
import PaceCore
import PaceTestSupport
@testable import ProfileFeature
@testable import SocialFeature
import SwiftUI
import Testing
import UIKit

/// Rendert die wichtigsten Screens mit Beispieldaten als PNG – zur visuellen Kontrolle in der CI (Artefakt
/// „snapshots“). Läuft nur, wenn `PACE_SNAPSHOT_DIR` gesetzt ist, und prüft nichts: Es entstehen nur Bilder.
///
/// Gerendert werden die Inhalte ohne Navigation und Scrollen (`ImageRenderer` kann keine UIKit-Container zeichnen);
/// systemeigene Controls wie Schalter erscheinen dabei als Platzhalter.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PACE_SNAPSHOT_DIR"] != nil))
struct ScreenSnapshotTests {
    private let width: CGFloat = 393

    @Test func homeDashboard() async throws {
        let (dashboard, _) = try await makeDashboard()
        await dashboard.loadStreakIfNeeded()
        let content = VStack(alignment: .leading, spacing: PaceSpacing.s) {
            HomeHeaderView(greeting: dashboard.greeting, onCustomize: {}, onNotifications: {})
            RegionRankCardsView(standings: dashboard.standings) { _ in }
            StepsTodayCardView(
                state: dashboard.activity.state,
                summary: dashboard.stepsToday,
                onEditGoal: {},
                onRetry: {}
            )
            WeekOverviewCardView(week: dashboard.week)
            StreakCardView(summary: dashboard.streakSummary, state: dashboard.streak.history.state)
            NeighborhoodCardView(standings: dashboard.standings) { _ in }
            FriendsPreviewCardView {}
            GroupsPreviewCardView {}
        }
        .padding(.horizontal, PaceSpacing.m)
        .padding(.vertical, PaceSpacing.m)
        try render(content, name: "home")
    }

    /// Kleine und große Varianten der Module.
    @Test func homeModuleSizes() async throws {
        let (dashboard, _) = try await makeDashboard()
        await dashboard.loadStreakIfNeeded()
        let small = VStack(alignment: .leading, spacing: PaceSpacing.s) {
            RegionRankCardsView(standings: dashboard.standings, size: .small) { _ in }
            WeekOverviewCardView(week: dashboard.week, size: .small)
            StreakCardView(summary: dashboard.streakSummary, state: dashboard.streak.history.state, size: .small)
            NeighborhoodCardView(standings: dashboard.standings, size: .small) { _ in }
            FriendsPreviewCardView(size: .small) {}
            GroupsPreviewCardView(size: .small) {}
        }
        .padding(PaceSpacing.m)
        try render(small, name: "home-small")

        let large = VStack(alignment: .leading, spacing: PaceSpacing.s) {
            RegionRankCardsView(standings: dashboard.standings, size: .large) { _ in }
            StepsTodayCardView(
                state: dashboard.activity.state,
                summary: dashboard.stepsToday,
                size: .large,
                onEditGoal: {},
                onRetry: {}
            )
            WeekOverviewCardView(week: dashboard.week, size: .large)
            StreakCardView(summary: dashboard.streakSummary, state: dashboard.streak.history.state, size: .large)
            NeighborhoodCardView(standings: dashboard.standings, level: .district, size: .large) { _ in }
        }
        .padding(PaceSpacing.m)
        try render(large, name: "home-large")
    }

    @Test func otherTabs() async throws {
        let (_, store) = try await makeDashboard()
        let leaderboard = LeaderboardViewModel(
            store: store,
            leaderboards: Self.leaderboards(),
            syncing: nil,
            calendar: Fixtures.activityCalendar,
            now: { Fixtures.date(2026, 10, 16, 12) },
            topLimit: 8
        )
        await leaderboard.loadIfNeeded()
        let (dashboard, _) = try await makeDashboard()
        let profile = ProfileViewModel(
            store: store,
            regions: RegionRepositoryStub(),
            appIcons: AppIconSettingStub(),
            streak: dashboard.streak,
            statistics: { dashboard.statistics(for: $0) },
            formatter: ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: Fixtures.activityCalendar)
        )
        await profile.load()
        await profile.loadActivity()

        try render(LeaderboardContent(viewModel: leaderboard).padding(PaceSpacing.m), name: "rankings")
        try render(SocialContent(viewModel: dashboard.social).padding(PaceSpacing.m), name: "social")
        let group = try #require(dashboard.social.groups.first)
        let detail = try #require(dashboard.social.detail(for: group))
        await detail.load()
        try render(GroupDetailContent(viewModel: detail).padding(PaceSpacing.m), name: "group")
        try render(ProfileContent(viewModel: profile).padding(PaceSpacing.m), name: "profile")
    }

    @Test func statistics() async throws {
        let (dashboard, _) = try await makeDashboard()
        await dashboard.streak.loadIfNeeded()
        let routes: [(StatisticsRoute, String)] = [
            (StatisticsRoute(period: .day, metric: .steps), "statistics-day"),
            (StatisticsRoute(period: .week, metric: .steps), "statistics-week"),
            (StatisticsRoute(period: .month, metric: .distance), "statistics-month-distance"),
        ]
        for (route, name) in routes {
            let statistics = dashboard.statistics(for: route)
            await statistics.loadHourly()
            guard case .report(let report) = statistics.content else {
                Issue.record("Kein Bericht für \(name)")
                continue
            }
            let content = StatisticsContent(
                report: report,
                hourly: statistics.hourly,
                onSelectPeriod: { _ in },
                onSelectMetric: { _ in },
                onPrevious: {},
                onNext: {},
                onSelectDay: { _ in }
            )
            try render(content.padding(PaceSpacing.m), name: name)
        }
    }

    // MARK: Beispieldaten (nur für Bilder)

    private func makeDashboard() async throws -> (HomeDashboardViewModel, ProfileStore) {
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

    private static func socialRepository() -> SocialRepositoryStub {
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

    private static func leaderboards() -> LeaderboardRepositoryStub {
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

    // MARK: Rendern

    private var directory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["PACE_SNAPSHOT_DIR"] ?? NSTemporaryDirectory())
    }

    /// Rendert reine SwiftUI-Inhalte (ohne ScrollView/Navigation) in Hell und Dunkel.
    private func render(_ content: some View, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let view = content
                .frame(width: width)
                .background(PaceColor.background)
                .environment(\.colorScheme, scheme)
                .environment(\.locale, Locale(identifier: "de_DE"))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
            let image = try #require(renderer.uiImage)
            try #require(image.pngData()).write(to: directory.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
        }
    }
}
