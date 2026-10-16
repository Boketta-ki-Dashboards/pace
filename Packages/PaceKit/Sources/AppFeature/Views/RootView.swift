import DesignSystem
import HealthPermissionFeature
import HomeFeature
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
                PaceLoadingView()
                    .paceScreenBackground()
            case .healthDataUnavailable:
                HealthDataUnavailableView()
            case .healthPermission(let viewModel):
                HealthPermissionView(viewModel: viewModel)
            case .home(let viewModel):
                HomeView(viewModel: viewModel)
            }
        }
        .animation(.default, value: router.route.kind)
        .tint(PaceColor.accent)
        .task { [router] in await router.start() }
    }
}
