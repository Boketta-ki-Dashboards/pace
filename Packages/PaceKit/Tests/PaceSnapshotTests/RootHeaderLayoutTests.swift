import DesignSystem
import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
import SwiftUI
import Testing
import UIKit

/// Köpfe der vier Haupttabs (Auftrag 5, C9): gleiche Höhe und gleiche Position von Wortmarke und Titel – mit und ohne
/// Aktionen rechts –, damit beim Wischen zwischen den Tabs nichts springt.
@MainActor
struct RootHeaderLayoutTests {
    private static let width: CGFloat = 361

    private func height(_ view: some View) -> CGFloat {
        let controller = UIHostingController(rootView: view.frame(width: Self.width))
        return controller.sizeThatFits(in: CGSize(width: Self.width, height: .greatestFiniteMagnitude)).height
    }

    @Test func allTabHeadersHaveTheSameHeight() async throws {
        let rankings = height(PaceRootHeader(title: "Rankings"))
        let social = height(PaceRootHeader(title: "Social") {
            Button {} label: { Image(systemName: "envelope.badge.person.crop") }
                .buttonStyle(.paceIcon)
            Button {} label: { Image(systemName: "gearshape") }
                .buttonStyle(.paceIcon)
        })
        let profile = height(PaceRootHeader(title: "Profil"))
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        let home = height(HomeHeaderView(viewModel: dashboard, onAddWidget: {}))

        #expect(rankings == PaceSpacing.xs + 2 * PaceRootHeader<EmptyView, PaceRootHeaderTitle>.rowHeight)
        #expect(social == rankings)
        #expect(profile == rankings)
        #expect(home == rankings, "Home-Kopf \(home) statt \(rankings)")
    }
}
