import Foundation
import HealthPermissionFeature
import HomeFeature

/// Oberste Navigationsebene der App. Jede Route besitzt das ViewModel ihres Screens.
public enum AppRoute {
    case launching
    case healthDataUnavailable
    case healthPermission(HealthPermissionViewModel)
    case home(HomeViewModel)

    public enum Kind: Hashable, Sendable {
        case launching
        case healthDataUnavailable
        case healthPermission
        case home
    }

    public var kind: Kind {
        switch self {
        case .launching: .launching
        case .healthDataUnavailable: .healthDataUnavailable
        case .healthPermission: .healthPermission
        case .home: .home
        }
    }
}
