import DesignSystem
import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import SwiftUI
import Testing
import UIKit

/// Ganze Bildschirme im echten Fenster (Navigation, Safe Areas, Textfelder, Tab-Leiste) – zur Kontrolle der
/// Bedienbarkeit: Zurück oben links, Chat-Eingabe sichtbar über der Tab-Leiste, nichts unter der Tab-Leiste verdeckt.
@MainActor
@Suite(.snapshotsEnabled)
struct LayoutSnapshotTests {
    /// Aufbau wie in `MainTabView`: Inhalt und Tab-Leiste untereinander.
    private func mainScreen(selected: Int, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            PaceTabBar(items: Self.tabItems, selection: .constant(selected))
        }
    }

    private static var tabItems: [PaceTabItem<Int>] {
        [
            PaceTabItem(value: 0, title: "Home", systemImage: "house", selectedSystemImage: "house.fill"),
            PaceTabItem(value: 1, title: "Rankings", systemImage: "chart.bar", selectedSystemImage: "chart.bar.fill"),
            PaceTabItem(value: 2, title: "Social", systemImage: "person.2", selectedSystemImage: "person.2.fill", badge: 3),
            PaceTabItem(value: 3, title: "Profil", systemImage: "person", selectedSystemImage: "person.fill"),
        ]
    }

    @Test func groupChatInNavigation() async throws {
        let (list, loader) = await ChatSnapshotData.groupSetup()
        let chat = list.chat(for: .group(id: ChatSnapshotData.groupID, name: "Smoking red"))
        await chat.load()
        let screen = mainScreen(selected: 2) {
            NavigationStack {
                ChatView(viewModel: chat, onOpenProfile: { _ in })
            }
        }
        .environment(\.paceImageLoader, loader)
        try await Snapshot.renderInWindow(screen, name: "layout-group-chat")
    }

    /// Kurzer Privatchat: Kopf muss oben bleiben (früher rutschte er mit wenigen Nachrichten nach unten).
    @Test func shortDirectChatInNavigation() async throws {
        let (list, _) = await ChatSnapshotData.directSetup()
        let chat = list.chat(for: .direct(ChatSnapshotData.mia))
        await chat.load()
        let screen = mainScreen(selected: 2) {
            NavigationStack {
                ChatView(viewModel: chat, onOpenProfile: { _ in })
            }
        }
        try await Snapshot.renderInWindow(screen, name: "layout-direct-chat")
    }

    /// Home ganz unten: Das letzte Widget endet über der Tab-Leiste.
    @Test func homeScrolledToTheEnd() async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        await dashboard.loadStreakIfNeeded()
        let screen = mainScreen(selected: 0) {
            HomeView(viewModel: dashboard)
        }
        try await Snapshot.renderInWindow(screen, name: "layout-home-end", prepare: Snapshot.scrollToBottom(in:))
    }

    /// Anpassen-Modus im echten Layout: Griffe, X, „Größe auswählen“.
    @Test func homeEditMode() async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        await dashboard.loadStreakIfNeeded()
        dashboard.beginEditing()
        let screen = mainScreen(selected: 0) {
            HomeView(viewModel: dashboard)
        }
        try await Snapshot.renderInWindow(screen, name: "layout-home-edit")
    }
}
