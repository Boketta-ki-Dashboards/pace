import SwiftUI

/// Typografie von Pace. Basiert auf Dynamic-Type-Stilen, damit Schriftgrößen-Einstellungen respektiert werden.
public enum PaceFont {
    public static var largeTitle: Font { .system(.largeTitle, design: .rounded, weight: .bold) }
    public static var title: Font { .system(.title2, design: .rounded, weight: .bold) }
    public static var headline: Font { .system(.headline, design: .rounded) }
    public static var body: Font { .body }
    public static var callout: Font { .callout }
    public static var caption: Font { .footnote }

    /// Große Kennzahl (z. B. die Schrittzahl). Die Größe sollte über `@ScaledMetric` skaliert werden.
    public static func metric(size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }
}
