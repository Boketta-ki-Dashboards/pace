import PaceCore
#if canImport(UIKit)
import UIKit

/// Alternative App-Icons über die öffentliche UIKit-API. Die Icons selbst stehen im Asset-Katalog der App
/// (`AppIconLight`, `AppIconDark`, eingetragen über ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES).
public struct SystemAppIconSetting: AppIconSetting {
    public init() {}

    @MainActor public var supportsAlternateIcons: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    @MainActor public var currentAlternateIconName: String? {
        UIApplication.shared.alternateIconName
    }

    @MainActor public func setAlternateIconName(_ name: String?) async throws {
        try await UIApplication.shared.setAlternateIconName(name)
    }
}
#endif
