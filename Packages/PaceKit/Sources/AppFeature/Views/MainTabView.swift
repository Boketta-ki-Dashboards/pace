import DesignSystem
import HomeFeature
import LeaderboardFeature
import ProfileFeature
import SwiftUI

/// Tab-Navigation der Main App.
struct MainTabView: View {
    @Bindable var viewModel: MainViewModel

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            HomeView(viewModel: viewModel.home)
                .tabItem { Label("Heute", systemImage: "figure.walk") }
                .tag(MainViewModel.Tab.home)

            LeaderboardView(viewModel: viewModel.leaderboard)
                .tabItem { Label("Rankings", systemImage: "trophy") }
                .tag(MainViewModel.Tab.rankings)

            ProfileView(viewModel: viewModel.profile)
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(MainViewModel.Tab.profile)
        }
    }
}
