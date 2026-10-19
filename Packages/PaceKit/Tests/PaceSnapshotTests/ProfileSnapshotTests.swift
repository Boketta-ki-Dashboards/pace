@testable import ActivityFeature
import DesignSystem
import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
@testable import ProfileFeature
import SwiftUI
import Testing

/// Profil und Einstellungen.
@MainActor
@Suite(.snapshotsEnabled)
struct ProfileSnapshotTests {
    @Test func profile() async throws {
        let (dashboard, store) = try await SnapshotFixtures.makeDashboard()
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
        try Snapshot.render(ProfileContent(viewModel: profile).padding(PaceSpacing.m), name: "profile")
    }
}
