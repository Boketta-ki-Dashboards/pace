import DesignSystem
import HomeFeature
import LeaderboardFeature
import ProfileFeature
import SocialFeature
import SwiftUI

/// Tab-Navigation der Main App: Home, Rankings, Social, Profil.
struct MainTabView: View {
    @Bindable var viewModel: MainViewModel

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            HomeView(viewModel: viewModel.dashboard)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(MainViewModel.Tab.home)

            LeaderboardView(viewModel: viewModel.leaderboard)
                .tabItem { Label("Rankings", systemImage: "chart.bar") }
                .tag(MainViewModel.Tab.rankings)

            SocialView(viewModel: viewModel.social)
                .tabItem { Label("Social", systemImage: "person.2") }
                .tag(MainViewModel.Tab.social)

            ProfileView(viewModel: viewModel.profile)
                .tabItem { Label("Profil", systemImage: "person") }
                .tag(MainViewModel.Tab.profile)
        }
        .tint(PaceColor.accentStrong)
        // Bewegungsdaten und Sync laufen für die ganze Main App, nicht nur, solange der Home-Tab offen ist.
        .activityUpdates(viewModel.home)
    }
}
