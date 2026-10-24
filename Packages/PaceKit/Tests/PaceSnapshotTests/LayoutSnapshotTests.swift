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
    /// Aufbau wie in `MainTabView`: Pager mit vier Seiten und Tab-Leiste untereinander; nur die gewählte Seite hat
    /// Inhalt.
    private func mainScreen(selected: Int, @ViewBuilder content: () -> some View) -> some View {
        MainScreenHarness(selected: selected, content: AnyView(content()))
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

    /// Wischen auf halbem Weg (Finger von rechts nach links, von Rankings Richtung Social): Rankings links, Social rechts
    /// je halb sichtbar, die Tab-Fläche liegt zwischen Rankings und Social.
    @Test func swipeHalfwayBetweenRankingsAndSocial() async throws {
        let screen = MainScreenHarness(selected: 1, content: AnyView(EmptyView()), labelsPages: true)
        try await Snapshot.renderInWindow(screen, name: "layout-pager-halfway") { view in
            Snapshot.scrollPager(in: view, toPosition: 1.5, pageCount: 4)
        }
    }
}

/// Nachbau von `MainTabView` für Fenster-Snapshots.
private struct MainScreenHarness: View {
    let selected: Int
    let content: AnyView
    var labelsPages = false

    @State private var selection: Int
    @State private var position: Double?

    init(selected: Int, content: AnyView, labelsPages: Bool = false) {
        self.selected = selected
        self.content = content
        self.labelsPages = labelsPages
        _selection = State(initialValue: selected)
    }

    private static let titles = ["Home", "Rankings", "Social", "Profil"]

    var body: some View {
        VStack(spacing: 0) {
            PaceTabPager(tabs: [0, 1, 2, 3], selection: $selection, isPagingEnabled: true, onPositionChange: { position = $0 }) { tab in
                if tab == selected && !labelsPages {
                    content
                } else {
                    VStack(alignment: .leading, spacing: PaceSpacing.s) {
                        PaceWordmark(height: 33)
                        Text(Self.titles[tab])
                            .font(.system(.title, weight: .bold))
                            .foregroundStyle(PaceColor.textPrimary)
                        Spacer()
                    }
                    .padding(PaceSpacing.m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .paceScreenBackground()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            PaceTabBar(items: Self.items, selection: $selection, position: position)
        }
    }

    private static var items: [PaceTabItem<Int>] {
        [
            PaceTabItem(value: 0, title: "Home", systemImage: "house", selectedSystemImage: "house.fill"),
            PaceTabItem(value: 1, title: "Rankings", systemImage: "chart.bar", selectedSystemImage: "chart.bar.fill"),
            PaceTabItem(value: 2, title: "Social", systemImage: "person.2", selectedSystemImage: "person.2.fill", badge: 3),
            PaceTabItem(value: 3, title: "Profil", systemImage: "person", selectedSystemImage: "person.fill"),
        ]
    }
}
