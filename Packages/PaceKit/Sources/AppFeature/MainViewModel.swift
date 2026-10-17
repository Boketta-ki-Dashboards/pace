import Foundation
import HomeFeature
import LeaderboardFeature
import Observation
import PaceCore
import ProfileFeature
import SocialFeature

/// Die Main App mit ihren Tabs. Weitere Tabs kommen als zusätzliche Fälle und ViewModels hinzu.
@MainActor
@Observable
public final class MainViewModel {
    public enum Tab: Hashable, Sendable {
        case home
        case rankings
        case social
        case profile
    }

    public var selectedTab: Tab = .home

    public let dashboard: HomeDashboardViewModel
    public let leaderboard: LeaderboardViewModel
    public let social: SocialViewModel
    public let profile: ProfileViewModel
    /// Gemeinsamer Profilstand für alle Tabs.
    public let store: ProfileStore

    public init(
        dashboard: HomeDashboardViewModel,
        leaderboard: LeaderboardViewModel,
        social: SocialViewModel,
        profile: ProfileViewModel,
        store: ProfileStore
    ) {
        self.dashboard = dashboard
        self.leaderboard = leaderboard
        self.social = social
        self.profile = profile
        self.store = store
    }

    /// Bewegungsdaten (für Aktualisierungs-Auslöser und Sync).
    public var home: HomeViewModel {
        dashboard.activity
    }

    /// Öffnet den Rankings-Tab, optional mit einer bestimmten Ebene (z. B. aus einer Karte auf Home).
    public func openRankings(scope: Region?) async {
        selectedTab = .rankings
        if let scope {
            await leaderboard.select(scope)
        }
    }

    public func openSocial() {
        selectedTab = .social
    }
}
