import SwiftUI
import UIKit

/// Farbpalette von Pace. Alle Farben unterstützen Light und Dark Mode.
public enum PaceColor {
    /// Markenfarbe für primäre Aktionen und Hervorhebungen.
    public static var accent: Color { Color(light: 0xE5482A, dark: 0xFF7452) }
    /// Vordergrund auf `accent`-Flächen.
    public static var onAccent: Color { .white }

    public static var background: Color { Color(uiColor: .systemGroupedBackground) }
    public static var surface: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    public static var textPrimary: Color { Color(uiColor: .label) }
    public static var textSecondary: Color { Color(uiColor: .secondaryLabel) }

    public static var success: Color { Color(light: 0x1E9E57, dark: 0x3DD17F) }
    public static var warning: Color { Color(light: 0xC77A00, dark: 0xFFB940) }
    public static var danger: Color { Color(light: 0xD32F2F, dark: 0xFF6B66) }
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
