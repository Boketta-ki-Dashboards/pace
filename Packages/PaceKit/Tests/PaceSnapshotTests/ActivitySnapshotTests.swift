@testable import ActivityFeature
import DesignSystem
import Foundation
@testable import HomeFeature
@testable import LeaderboardFeature
import PaceCore
import PaceTestSupport
import SwiftUI
import Testing

/// Statistiken, Kalender, Tagesdetails und Rankings.
@MainActor
@Suite(.snapshotsEnabled)
struct ActivitySnapshotTests {
    @Test func rankings() async throws {
        let (_, store) = try await SnapshotFixtures.makeDashboard()
        let leaderboard = LeaderboardViewModel(
            store: store,
            leaderboards: SnapshotFixtures.leaderboards(),
            syncing: nil,
            calendar: Fixtures.activityCalendar,
            now: { Fixtures.date(2026, 10, 16, 12) },
            topLimit: 8
        )
        await leaderboard.loadIfNeeded()
        try Snapshot.render(LeaderboardContent(viewModel: leaderboard).padding(PaceSpacing.m), name: "rankings")
    }

    @Test func statistics() async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
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
            try Snapshot.render(content.padding(PaceSpacing.m), name: name)
        }
    }
}
