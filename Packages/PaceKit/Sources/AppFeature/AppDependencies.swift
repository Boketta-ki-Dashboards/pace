import Foundation
import PaceCore

/// Alle Services, die die Features benötigen – ausschließlich als Protokolle.
/// Die konkreten Implementierungen werden im Composition Root der App erzeugt.
public struct AppDependencies: Sendable {
    public let healthAuthorization: any HealthAuthorizationProviding
    public let activityData: any ActivityDataProviding

    public init(
        healthAuthorization: any HealthAuthorizationProviding,
        activityData: any ActivityDataProviding
    ) {
        self.healthAuthorization = healthAuthorization
        self.activityData = activityData
    }
}
