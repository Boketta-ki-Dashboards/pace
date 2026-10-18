import Foundation
import HomeFeature
import PaceCore

/// Alle Services, die die Features benötigen – ausschließlich als Protokolle.
/// Die konkreten Implementierungen werden im Composition Root der App erzeugt.
public struct AppDependencies: Sendable {
    public enum Backend: Sendable {
        case available(BackendServices)
        /// Das Backend ist nicht konfiguriert (z. B. fehlt `Config/Pace.xcconfig`).
        case unavailable(reason: String)
    }

    public let healthAuthorization: any HealthAuthorizationProviding
    public let activityData: any ActivityDataProviding
    public let backend: Backend
    /// Tagesziel und Aufbau des Home-Dashboards (nur auf dem Gerät).
    public let homePreferences: any HomePreferencesStoring
    /// Verlauf des Tagesziels (nur auf dem Gerät).
    public let stepGoals: any StepGoalStoring
    /// Längste persönliche Serie (nur auf dem Gerät).
    public let streakRecords: any StepStreakRecordStoring
    /// Wechsel des App-Icons (Profil → Darstellung).
    public let appIcons: any AppIconSetting

    public init(
        healthAuthorization: any HealthAuthorizationProviding,
        activityData: any ActivityDataProviding,
        backend: Backend,
        homePreferences: any HomePreferencesStoring = UserDefaultsHomePreferencesStore(),
        stepGoals: any StepGoalStoring = UserDefaultsStepGoalStore(),
        streakRecords: any StepStreakRecordStoring = UserDefaultsStepStreakRecordStore(),
        appIcons: any AppIconSetting = UnsupportedAppIconSetting()
    ) {
        self.healthAuthorization = healthAuthorization
        self.activityData = activityData
        self.backend = backend
        self.homePreferences = homePreferences
        self.stepGoals = stepGoals
        self.streakRecords = streakRecords
        self.appIcons = appIcons
    }
}

/// Backend-Dienste hinter den Protokollen aus PaceCore.
public struct BackendServices: Sendable {
    public let auth: any AuthProviding
    public let profiles: any ProfileRepository
    public let regions: any RegionRepository
    public let activitySync: any ActivitySyncRepository
    public let leaderboards: any LeaderboardRepository
    public let profileCache: any ProfileCaching

    public init(
        auth: any AuthProviding,
        profiles: any ProfileRepository,
        regions: any RegionRepository,
        activitySync: any ActivitySyncRepository,
        leaderboards: any LeaderboardRepository,
        profileCache: any ProfileCaching = UserDefaultsProfileCache()
    ) {
        self.auth = auth
        self.profiles = profiles
        self.regions = regions
        self.activitySync = activitySync
        self.leaderboards = leaderboards
        self.profileCache = profileCache
    }
}
