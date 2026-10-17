import Foundation
import HomeFeature
import LeaderboardFeature
import Observation
import PaceCore
import ProfileFeature

/// Die Main App mit ihren Tabs. Weitere Tabs (z. B. Social) kommen als zusätzliche Fälle und ViewModels hinzu.
@MainActor
@Observable
public final class MainViewModel {
    public enum Tab: Hashable, Sendable {
        case home
        case rankings
        case profile
    }

    public var selectedTab: Tab = .home

    public let home: HomeViewModel
    public let leaderboard: LeaderboardViewModel
    public let profile: ProfileViewModel
    /// Gemeinsamer Profilstand für alle Tabs.
    public let store: ProfileStore

    public init(home: HomeViewModel, leaderboard: LeaderboardViewModel, profile: ProfileViewModel, store: ProfileStore) {
        self.home = home
        self.leaderboard = leaderboard
        self.profile = profile
        self.store = store
    }
}
