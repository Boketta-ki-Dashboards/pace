@testable import ActivityFeature
import DesignSystem
import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import SwiftUI
import Testing

/// Home-Dashboard und Module in ihren Größen.
@MainActor
@Suite(.snapshotsEnabled)
struct HomeSnapshotTests {
    @Test func homeDashboard() async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
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
            FriendsPreviewCardView(social: dashboard.social) {}
            GroupsPreviewCardView(social: dashboard.social) {}
        }
        .padding(.horizontal, PaceSpacing.m)
        .padding(.vertical, PaceSpacing.m)
        try Snapshot.render(content, name: "home")
    }

    /// Kleine und große Varianten der Module.
    @Test func homeModuleSizes() async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        await dashboard.loadStreakIfNeeded()
        let small = VStack(alignment: .leading, spacing: PaceSpacing.s) {
            RegionRankCardsView(standings: dashboard.standings, size: .small) { _ in }
            WeekOverviewCardView(week: dashboard.week, size: .small)
            StreakCardView(summary: dashboard.streakSummary, state: dashboard.streak.history.state, size: .small)
            NeighborhoodCardView(standings: dashboard.standings, size: .small) { _ in }
            FriendsPreviewCardView(social: dashboard.social, size: .small) {}
            GroupsPreviewCardView(social: dashboard.social, size: .small) {}
        }
        .padding(PaceSpacing.m)
        try Snapshot.render(small, name: "home-small")

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
            FriendsPreviewCardView(social: dashboard.social, size: .large) {}
            GroupsPreviewCardView(social: dashboard.social, size: .large) {}
        }
        .padding(PaceSpacing.m)
        try Snapshot.render(large, name: "home-large")
    }
}
