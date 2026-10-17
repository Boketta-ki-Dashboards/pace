import Foundation
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

    public init(
        healthAuthorization: any HealthAuthorizationProviding,
        activityData: any ActivityDataProviding,
        backend: Backend
    ) {
        self.healthAuthorization = healthAuthorization
        self.activityData = activityData
        self.backend = backend
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
