import Foundation

/// Pace ist durchgehend deutsch. Zahlen und Datumsangaben folgen deshalb immer dem deutschen Format („8.421“),
/// unabhängig von der Regionseinstellung des iPhones – sonst stünde „8,421 Schritte“ neben deutschem Text.
public enum PaceLocale {
    public static let german = Locale(identifier: "de_DE")
}

extension Int {
    /// `8.421`
    public var paceFormatted: String {
        formatted(.number.locale(PaceLocale.german))
    }
}
