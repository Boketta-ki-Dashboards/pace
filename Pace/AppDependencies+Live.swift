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
            backend: makeBackend()
        )
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
                leaderboards: backend.leaderboards
            ))
        } catch {
            return .unavailable(reason: error.message)
        }
    }
}
