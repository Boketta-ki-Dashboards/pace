import SwiftUI
import UIKit

/// Farbpalette von Pace (grüne Markenidentität). Alle Farben passen sich an Light und Dark Mode an.
public enum PaceColor {
    // MARK: Marke

    /// Farbe der Wortmarke und großer Markenflächen: tiefes Grün, im Dark Mode Mint.
    public static var brand: Color { Color(light: 0x072D20, dark: 0x8EF5D8) }
    /// Akzent für Fortschritt, Links und Symbole.
    public static var accent: Color { Color(light: 0x16784C, dark: 0x86F3D3) }
    /// Gefüllte Buttons, ausgewählte Elemente, Fortschrittsring.
    public static var accentStrong: Color { Color(light: 0x075237, dark: 0x88F7D8) }
    /// Vordergrund auf `accentStrong`- und `accent`-Flächen.
    public static var onAccent: Color { Color(light: 0xFFFFFF, dark: 0x06211A) }
    /// Zarte Hervorhebung, z. B. die eigene Zeile im Ranking.
    public static var accentSoft: Color { Color(light: 0xDDF8EC, dark: 0x0F2A24) }

    /// Kompakte Aktions-Buttons in Zeilen („Hinzufügen“, „Annehmen“): etwas helleres Grün, im Dark Mode Mint.
    public static var actionFill: Color { Color(light: 0x07774B, dark: 0x88F7D8) }
    /// Aktiver Tab und weiche Aktionsflächen („Freund hinzufügen“): zartes Mint, im Dark Mode Mint.
    public static var selectionFill: Color { Color(light: 0xD3F9EA, dark: 0x8EF8DC) }
    /// Vordergrund auf `selectionFill`.
    public static var onSelection: Color { Color(light: 0x063D29, dark: 0x06211A) }
    /// Zielerreichte Tage im Kalender: frisches Grün, im Dark Mode Mint (mit dunkler Schrift).
    public static var goalReachedFill: Color { Color(light: 0x3BBF79, dark: 0x7FEFC5) }
    /// Text auf `goalReachedFill`.
    public static var onGoalReached: Color { Color(light: 0x07301F, dark: 0x06211A) }

    // MARK: Flächen

    public static var background: Color { Color(light: 0xF8F9F7, dark: 0x0B1315) }
    /// Karten.
    public static var surface: Color { Color(light: 0xFFFFFF, dark: 0x111A1D) }
    /// Flächen innerhalb von Karten (Kacheln, Zeilen).
    public static var surfaceSecondary: Color { Color(light: 0xFFFFFF, dark: 0x152024) }
    /// Feine Ränder um Karten und Kacheln.
    public static var border: Color { Color(light: 0xE7EAE6, dark: 0x232E32) }
    /// Eingabefelder, nicht gewählte Segmente und leere Kalendertage.
    public static var fieldBackground: Color { Color(light: 0xF1F2F5, dark: 0x172125) }
    /// Hintergrund von Fortschrittsbalken und -ringen.
    public static var track: Color { Color(light: 0xE1E4E2, dark: 0x343C3E) }

    // MARK: Text

    public static var textPrimary: Color { Color(light: 0x0B120F, dark: 0xF3F7F5) }
    /// Sekundärer Text mit leichtem Blaustich, wie im Pace-Design.
    public static var textSecondary: Color { Color(light: 0x5F6684, dark: 0xA3AEB8) }

    // MARK: Diagramme

    /// Schwächste Stufe in Wochenübersichten; die stärkste ist `accentStrong`.
    public static var chartLow: Color { Color(light: 0xA7DDBF, dark: 0x4E9F86) }

    // MARK: Serie

    /// Flamme der persönlichen Serie.
    public static var streak: Color { Color(light: 0xE8590C, dark: 0xFF922B) }

    // MARK: Status

    public static var success: Color { Color(light: 0x1E8A50, dark: 0x6EE7A0) }
    public static var warning: Color { Color(light: 0xB86E00, dark: 0xFFB940) }
    public static var danger: Color { Color(light: 0xC62828, dark: 0xFF6B66) }
}

extension Color {
    /// Erzeugt eine Farbe, die sich automatisch an Light/Dark Mode anpasst.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
