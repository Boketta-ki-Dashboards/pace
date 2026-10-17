import DesignSystem
import HealthPermissionFeature
import OnboardingFeature
import SwiftUI

/// Wurzel der UI: rendert die aktuelle Route des `AppRouter`.
public struct RootView: View {
    private let router: AppRouter

    public init(router: AppRouter) {
        self.router = router
    }

    public var body: some View {
        Group {
            switch router.route {
            case .launching:
                // Wie der Startbildschirm: Wortmarke auf ruhigem Hintergrund.
                PaceWordmark(height: 52)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .paceScreenBackground()
            case .healthDataUnavailable:
                HealthDataUnavailableView()
            case .healthPermission(let viewModel):
                HealthPermissionView(viewModel: viewModel)
            case .backendUnavailable(let message):
                BackendUnavailableView(message: message)
            case .connecting:
                PaceLoadingView("Verbinde mit Pace …")
                    .paceScreenBackground()
            case .connectionFailed(let message):
                ConnectionFailedView(message: message) {
                    Task { await router.connect() }
                }
            case .onboarding(let viewModel):
                OnboardingView(viewModel: viewModel)
            case .main(let viewModel):
                MainTabView(viewModel: viewModel)
            }
        }
        .animation(.default, value: router.route.kind)
        .tint(PaceColor.accent)
        .task { [router] in await router.start() }
    }
}
