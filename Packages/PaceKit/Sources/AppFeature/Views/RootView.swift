import DesignSystem
import HealthPermissionFeature
import OnboardingFeature
import PaceCore
import SwiftUI

/// Wurzel der UI: rendert die aktuelle Route des `AppRouter`.
public struct RootView: View {
    private let router: AppRouter
    /// Lädt Profil-, Gruppen- und Chatbilder für alle Ansichten (mit Zwischenspeicher).
    @State private var imageLoader: PaceImageLoader?

    public init(router: AppRouter) {
        self.router = router
        _imageLoader = State(initialValue: router.media.map { PaceImageLoader(repository: $0) })
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
                PaceLoadingView(PaceLocalization.text(de: "Verbinde mit Pace …", en: "Connecting to Pace …", ru: "Подключение к Pace …"))
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
        .preferredColorScheme(router.settings.appearance.colorScheme)
        // Systemsteuerelemente (Datumsauswahl, Teilen-Dialog) in der gewählten Sprache.
        .environment(\.locale, PaceLocalization.shared.locale)
        .environment(\.paceImageLoader, imageLoader)
        .task { [router] in await router.start() }
    }
}

extension AppearancePreference {
    /// `nil` folgt der Einstellung des iPhones.
    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
