import AppFeature
import Foundation
import PaceBackend
import PaceHealth

extension AppDependencies {
    /// Composition Root: Hier – und nur hier – werden die konkreten Services erzeugt.
    static func live() -> AppDependencies {
        let healthKit = HealthKitService()
        return AppDependencies(
            healthAuthorization: healthKit,
            activityData: healthKit,
            liveSteps: PedometerLiveSteps.appSource(),
            backend: makeBackend(),
            appIcons: SystemAppIconSetting(),
            notifications: UserNotificationScheduler(),
            appVersion: appVersion,
            gifSearch: GIPHYSearchService.fromInfoDictionary(Bundle.main.infoDictionary ?? [:]),
            // Optional: PACE_SUPPORT_EMAIL in Config/Pace.xcconfig (leer = keine Support-E-Mail in der App).
            supportEmail: Bundle.main.infoDictionary?["PaceSupportEmail"] as? String
        )
    }

    /// z. B. `0.1.0 (1)`.
    private static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "–"
        let build = info["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    /// Supabase mit den Werten aus `Config/Pace.xcconfig` (über die Info.plist). Fehlt die Konfiguration oder ist
    /// sie unzulässig (z. B. ein Secret Key), startet die App ohne Backend und zeigt einen Hinweis.
    private static func makeBackend() -> Backend {
        do {
            let configuration = try BackendConfiguration.fromInfoDictionary(Bundle.main.infoDictionary ?? [:])
            let backend = SupabaseBackend(configuration: configuration)
            return .available(BackendServices(
                auth: backend.auth,
                profiles: backend.profiles,
                regions: backend.regions,
                activitySync: backend.activitySync,
                leaderboards: backend.leaderboards,
                social: backend.social,
                chat: backend.chat,
                media: backend.media,
                account: backend.account,
                profileDetails: backend.profileDetails
            ))
        } catch {
            return .unavailable(reason: error.message)
        }
    }
}
