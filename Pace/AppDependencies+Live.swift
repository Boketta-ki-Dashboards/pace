import AppFeature
import PaceHealth

extension AppDependencies {
    /// Composition Root: Hier – und nur hier – werden die konkreten Services erzeugt.
    static func live() -> AppDependencies {
        let healthKit = HealthKitService()
        return AppDependencies(healthAuthorization: healthKit, activityData: healthKit)
    }
}
