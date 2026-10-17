import SwiftUI

/// Typografie von Pace: SF Pro mit klaren Gewichten. Basiert auf Dynamic-Type-Stilen, damit Schriftgrößen-Einstellungen
/// respektiert werden.
public enum PaceFont {
    public static var largeTitle: Font { .system(.largeTitle, weight: .bold) }
    public static var title: Font { .system(.title2, weight: .bold) }
    /// Überschrift einer Karte, z. B. „Deine Schritte heute“.
    public static var cardTitle: Font { .system(.title3, weight: .semibold) }
    public static var headline: Font { .system(.headline, weight: .semibold) }
    public static var body: Font { .body }
    public static var callout: Font { .callout }
    public static var caption: Font { .footnote }
    public static var micro: Font { .system(.caption2, weight: .medium) }

    /// Große Kennzahl (z. B. die Schrittzahl). Die Größe sollte über `@ScaledMetric` skaliert werden.
    public static func metric(size: CGFloat) -> Font {
        .system(size: size, weight: .heavy)
    }
}
