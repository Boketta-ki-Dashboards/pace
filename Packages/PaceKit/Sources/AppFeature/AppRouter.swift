import Foundation
import HealthPermissionFeature
import HomeFeature
import Observation
import PaceCore

/// Entscheidet, welcher Screen gezeigt wird, und erzeugt die zugehörigen ViewModels.
@MainActor
@Observable
public final class AppRouter {
    public private(set) var route: AppRoute = .launching

    @ObservationIgnored private let dependencies: AppDependencies

    public init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    /// Bestimmt beim App-Start die erste Route. Weitere Aufrufe haben keine Wirkung.
    public func start() async {
        guard case .launching = route else { return }

        guard dependencies.healthAuthorization.isHealthDataAvailable else {
            route = .healthDataUnavailable
            return
        }

        // Lässt sich der Status nicht ermitteln, zeigen wir den Permission-Screen. Eine erneute Anfrage ist
        // unschädlich: HealthKit zeigt den Dialog nur, wenn noch nicht gefragt wurde.
        let status = try? await dependencies.healthAuthorization.authorizationRequestStatus()
        guard case .launching = route else { return }

        switch status {
        case .alreadyRequested:
            showHome()
        case .shouldRequest, .unknown, nil:
            showHealthPermission()
        }
    }

    private func showHealthPermission() {
        let viewModel = HealthPermissionViewModel(authorization: dependencies.healthAuthorization) { [weak self] in
            self?.showHome()
        }
        route = .healthPermission(viewModel)
    }

    private func showHome() {
        route = .home(HomeViewModel(stepCounts: dependencies.stepCounts))
    }
}
