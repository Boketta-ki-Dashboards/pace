import Foundation
import HealthPermissionFeature
import OnboardingFeature

/// Oberste Navigationsebene der App. Jede Route besitzt das ViewModel ihres Screens.
public enum AppRoute {
    case launching
    case healthDataUnavailable
    case healthPermission(HealthPermissionViewModel)
    /// Das Backend ist nicht konfiguriert (Entwicklungsumgebung ohne `Config/Pace.xcconfig`).
    case backendUnavailable(message: String)
    /// Sitzung und Profil werden geprüft.
    case connecting
    case connectionFailed(message: String)
    case onboarding(OnboardingViewModel)
    case main(MainViewModel)
    /// Das Konto wurde gelöscht; ein neuer Start führt in das Onboarding mit einer neuen Identität.
    case accountDeleted

    public enum Kind: Hashable, Sendable {
        case launching
        case healthDataUnavailable
        case healthPermission
        case backendUnavailable
        case connecting
        case connectionFailed
        case onboarding
        case main
        case accountDeleted
    }

    public var kind: Kind {
        switch self {
        case .launching: .launching
        case .healthDataUnavailable: .healthDataUnavailable
        case .healthPermission: .healthPermission
        case .backendUnavailable: .backendUnavailable
        case .connecting: .connecting
        case .connectionFailed: .connectionFailed
        case .onboarding: .onboarding
        case .main: .main
        case .accountDeleted: .accountDeleted
        }
    }
}
