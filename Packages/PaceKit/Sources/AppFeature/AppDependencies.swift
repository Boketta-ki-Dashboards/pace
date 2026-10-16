import Foundation
import PaceCore

/// Alle Services, die die Features benötigen – ausschließlich als Protokolle.
/// Die konkreten Implementierungen werden im Composition Root der App erzeugt.
public struct AppDependencies: Sendable {
    public let healthAuthorization: any HealthAuthorizationProviding
    public let stepCounts: any StepCountProviding

    public init(
        healthAuthorization: any HealthAuthorizationProviding,
        stepCounts: any StepCountProviding
    ) {
        self.healthAuthorization = healthAuthorization
        self.stepCounts = stepCounts
    }
}
