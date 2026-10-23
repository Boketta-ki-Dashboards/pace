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
    /// Schnelle Schrittwerte des Bewegungssensors für die Anzeige im Vordergrund.
    public let liveSteps: any LiveStepCounting
    public let backend: Backend
    /// Tagesziel und Aufbau des Home-Dashboards (nur auf dem Gerät).
    public let homePreferences: any HomePreferencesStoring
    /// Verlauf des Tagesziels (nur auf dem Gerät).
    public let stepGoals: any StepGoalStoring
    /// Längste persönliche Serie (nur auf dem Gerät).
    public let streakRecords: any StepStreakRecordStoring
    /// Wechsel des App-Icons (Profil → Darstellung).
    public let appIcons: any AppIconSetting
    /// Darstellung, Sprache und Erinnerungen (nur auf dem Gerät).
    public let preferences: any AppPreferencesStoring
    /// Lokale Mitteilungen (Erinnerung an das Tagesziel).
    public let notifications: any LocalNotificationScheduling
    /// Versionsangabe für „Hilfe & Rechtliches“, z. B. `0.1.0 (1)`.
    public let appVersion: String
    /// Alle nur auf dem Gerät gespeicherten Pace-Daten (Datenexport, Löschen nach dem Löschen des Kontos).
    public let localData: any LocalAccountDataStoring

    public init(
        healthAuthorization: any HealthAuthorizationProviding,
        activityData: any ActivityDataProviding,
        liveSteps: any LiveStepCounting = NoLiveStepCounting(),
        backend: Backend,
        homePreferences: any HomePreferencesStoring = UserDefaultsHomePreferencesStore(),
        stepGoals: any StepGoalStoring = UserDefaultsStepGoalStore(),
        streakRecords: any StepStreakRecordStoring = UserDefaultsStepStreakRecordStore(),
        appIcons: any AppIconSetting = UnsupportedAppIconSetting(),
        preferences: any AppPreferencesStoring = UserDefaultsAppPreferencesStore(),
        notifications: any LocalNotificationScheduling = NoLocalNotifications(),
        appVersion: String = "",
        localData: any LocalAccountDataStoring = UserDefaultsLocalAccountData()
    ) {
        self.healthAuthorization = healthAuthorization
        self.activityData = activityData
        self.liveSteps = liveSteps
        self.backend = backend
        self.homePreferences = homePreferences
        self.stepGoals = stepGoals
        self.streakRecords = streakRecords
        self.appIcons = appIcons
        self.preferences = preferences
        self.notifications = notifications
        self.appVersion = appVersion
        self.localData = localData
    }
}

/// Ohne Mitteilungen (Tests, Vorschauen).
public struct NoLocalNotifications: LocalNotificationScheduling {
    public init() {}
    public func authorization() async -> NotificationAuthorization { .denied }
    public func requestAuthorization() async -> Bool { false }
    public func scheduleGoalReminders(_ notifications: [PlannedNotification]) async {}
    public func cancelGoalReminders() async {}
    public func deliver(_ notification: PlannedNotification) async {}
}

/// Backend-Dienste hinter den Protokollen aus PaceCore.
public struct BackendServices: Sendable {
    public let auth: any AuthProviding
    public let profiles: any ProfileRepository
    public let regions: any RegionRepository
    public let activitySync: any ActivitySyncRepository
    public let leaderboards: any LeaderboardRepository
    /// Freunde und Gruppen; `nil`, wenn nicht angebunden (z. B. in Tests).
    public let social: (any SocialRepository)?
    /// Unterhaltungen; `nil`, wenn nicht angebunden.
    public let chat: (any ChatRepository)?
    /// Profil-, Gruppen- und Chatbilder; `nil`, wenn nicht angebunden.
    public let media: (any MediaRepository)?
    /// Datenexport, Kontolöschung, Rückmeldungen; `nil`, wenn nicht angebunden.
    public let account: (any AccountRepository)?
    public let profileCache: any ProfileCaching

    public init(
        auth: any AuthProviding,
        profiles: any ProfileRepository,
        regions: any RegionRepository,
        activitySync: any ActivitySyncRepository,
        leaderboards: any LeaderboardRepository,
        social: (any SocialRepository)? = nil,
        chat: (any ChatRepository)? = nil,
        media: (any MediaRepository)? = nil,
        account: (any AccountRepository)? = nil,
        profileCache: any ProfileCaching = UserDefaultsProfileCache()
    ) {
        self.auth = auth
        self.profiles = profiles
        self.regions = regions
        self.activitySync = activitySync
        self.leaderboards = leaderboards
        self.social = social
        self.chat = chat
        self.media = media
        self.account = account
        self.profileCache = profileCache
    }
}
