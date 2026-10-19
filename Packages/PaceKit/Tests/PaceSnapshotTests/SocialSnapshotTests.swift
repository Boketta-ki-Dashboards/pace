import DesignSystem
import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import SwiftUI
import Testing

/// Social-Hauptseite, Gruppen und Chats.
@MainActor
@Suite(.snapshotsEnabled)
struct SocialSnapshotTests {
    @Test func socialAndGroup() async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        try Snapshot.render(SocialContent(viewModel: dashboard.social).padding(PaceSpacing.m), name: "social")
        let group = try #require(dashboard.social.groups.first)
        let detail = try #require(dashboard.social.detail(for: group))
        await detail.load()
        try Snapshot.render(GroupDetailContent(viewModel: detail).padding(PaceSpacing.m), name: "group")
    }
}
