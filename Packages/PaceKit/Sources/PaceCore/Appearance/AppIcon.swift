import Foundation

/// Wählbare App-Icons (Profil → Darstellung → App-Icon). Alle zeigen die Original-Wortmarke.
public enum AppIconChoice: String, CaseIterable, Identifiable, Sendable {
    /// Primäres Icon: folgt der Darstellung des Home-Bildschirms (hell, dunkel oder getönt; ab iOS 18).
    case automatic
    /// Wortmarke in Dunkelgrün auf hellem Grund (das Original-Logo).
    case light
    /// Wortmarke in Mint auf dunklem Grund.
    case dark

    public var id: String { rawValue }

    /// Name des alternativen Icons im Asset-Katalog; `nil` steht für das primäre Icon.
    public var alternateIconName: String? {
        switch self {
        case .automatic: nil
        case .light: "AppIconLight"
        case .dark: "AppIconDark"
        }
    }

    /// Unbekannte Namen (z. B. ein entferntes Icon aus einer älteren Version) gelten als primäres Icon.
    public init(alternateIconName: String?) {
        self = Self.allCases.first { $0.alternateIconName == alternateIconName } ?? .automatic
    }

    public var title: String {
        switch self {
        case .automatic: "Automatisch"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }
}

/// Wechselt das App-Icon (in der App: `UIApplication`). iOS merkt sich die Wahl selbst, auch über Updates hinweg.
public protocol AppIconSetting: Sendable {
    @MainActor var supportsAlternateIcons: Bool { get }
    @MainActor var currentAlternateIconName: String? { get }
    /// iOS bestätigt den Wechsel selbst mit einem kurzen Hinweis; die App zeigt keine zusätzliche Meldung.
    @MainActor func setAlternateIconName(_ name: String?) async throws
}

/// Für Umgebungen ohne alternative Icons (Tests, Vorschauen).
public struct UnsupportedAppIconSetting: AppIconSetting {
    public init() {}

    public var supportsAlternateIcons: Bool { false }
    public var currentAlternateIconName: String? { nil }

    public func setAlternateIconName(_ name: String?) async throws {
        throw CocoaError(.featureUnsupported)
    }
}
