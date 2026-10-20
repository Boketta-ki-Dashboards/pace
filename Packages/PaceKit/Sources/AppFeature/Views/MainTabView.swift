import DesignSystem
import HomeFeature
import LeaderboardFeature
import PaceCore
import ProfileFeature
import SocialFeature
import SwiftUI

/// Tab-Navigation der Main App: Home, Rankings, Social, Profil – mit der Pace-Tab-Leiste.
///
/// Die Tabs werden beim ersten Öffnen erzeugt und bleiben danach erhalten (wie bei `TabView`), damit Navigation und
/// Scrollposition beim Wechseln bestehen bleiben.
struct MainTabView: View {
    @Bindable var viewModel: MainViewModel
    @State private var openedTabs: Set<MainViewModel.Tab> = [.home]

    var body: some View {
        ZStack {
            ForEach(MainViewModel.Tab.allCases, id: \.self) { tab in
                if openedTabs.contains(tab) {
                    let isSelected = viewModel.selectedTab == tab
                    content(for: tab)
                        .opacity(isSelected ? 1 : 0)
                        .allowsHitTesting(isSelected)
                        .accessibilityHidden(!isSelected)
                        .zIndex(isSelected ? 1 : 0)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PaceTabBar(items: tabItems, selection: $viewModel.selectedTab)
        }
        // Die Tastatur schiebt die Inhalte nach oben, die Tab-Leiste bleibt unten (sie liegt dann unter der Tastatur).
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: viewModel.selectedTab, initial: true) { _, tab in
            openedTabs.insert(tab)
        }
        .onChange(of: viewModel.selectedTab) { _, tab in
            Task { await viewModel.didSelect(tab) }
        }
        // Ist das Tagesziel erreicht, entfällt die Erinnerung für heute.
        .onChange(of: viewModel.profile.notifications.todayGoalReached) {
            Task { await viewModel.profile.notifications.reschedule() }
        }
        // Bewegungsdaten und Sync laufen für die ganze Main App, nicht nur, solange der Home-Tab offen ist.
        .activityUpdates(viewModel.home)
    }

    @ViewBuilder
    private func content(for tab: MainViewModel.Tab) -> some View {
        switch tab {
        case .home: HomeView(viewModel: viewModel.dashboard)
        case .rankings: LeaderboardView(viewModel: viewModel.leaderboard)
        case .social: SocialView(viewModel: viewModel.social)
        case .profile: ProfileView(viewModel: viewModel.profile)
        }
    }

    private var tabItems: [PaceTabItem<MainViewModel.Tab>] {
        [
            PaceTabItem(
                value: .home,
                title: PaceLocalization.text(de: "Home", en: "Home", ru: "Главная"),
                systemImage: "house",
                selectedSystemImage: "house.fill"
            ),
            PaceTabItem(
                value: .rankings,
                title: PaceLocalization.text(de: "Rankings", en: "Rankings", ru: "Рейтинги"),
                systemImage: "chart.bar",
                selectedSystemImage: "chart.bar.fill"
            ),
            PaceTabItem(
                value: .social,
                title: PaceLocalization.text(de: "Social", en: "Social", ru: "Друзья"),
                systemImage: "person.2",
                selectedSystemImage: "person.2.fill",
                // Ungelesene Nachrichten aller Chats.
                badge: viewModel.social.chats.unreadCount
            ),
            PaceTabItem(
                value: .profile,
                title: PaceLocalization.text(de: "Profil", en: "Profile", ru: "Профиль"),
                systemImage: "person",
                selectedSystemImage: "person.fill"
            ),
        ]
    }
}
