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
            NeighborhoodCardView(standings: dashboard.standings) { _ in }
            FriendsPreviewCardView {}
            GroupsPreviewCardView {}
        }
        .padding(.horizontal, PaceSpacing.m)
        .padding(.vertical, PaceSpacing.m)
        try render(content, name: "home")
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
        let profile = ProfileViewModel(store: store, regions: RegionRepositoryStub(), appIcons: AppIconSettingStub())
        await profile.load()

        try render(LeaderboardContent(viewModel: leaderboard).padding(PaceSpacing.m), name: "rankings")
        try render(SocialContent(viewModel: SocialViewModel()).padding(PaceSpacing.m), name: "social")
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
                let steps = 5_000 + (offset * 7_919).magnitude % 8_000
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
        await standings.load()

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
            activityData: health,
            store: store,
            calendar: calendar,
            formatter: ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: calendar),
            now: now
        )
        return (dashboard, store)
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
