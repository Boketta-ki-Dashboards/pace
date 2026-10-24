import Foundation

/// Rechenregeln für das Wischen zwischen den Haupttabs (Home – Rankings – Social – Profil), ohne SwiftUI.
///
/// Richtung (verbindlich laut Auftrag): Die Fingerbewegung nach **rechts** führt zum **nächsten** Tab
/// (Home → Rankings → Social → Profil), nach links zurück. Die Seiten bewegen sich dabei mit dem Finger; der nächste Tab
/// erscheint deshalb von links. Dafür liegen die Seiten in der Scrollansicht in umgekehrter Reihenfolge
/// (`advancesWithFingerMovingRight == true`). Mit `false` gilt die iOS-übliche Richtung.
public enum PaceTabPaging {
    /// Richtung der Haupttab-Navigation – eine Stelle zum Umstellen.
    public static let advancesWithFingerMovingRight = true

    /// Reihenfolge der Seiten von links nach rechts in der Scrollansicht.
    public static func visualOrder<Tab>(_ tabs: [Tab], advancesWithFingerMovingRight: Bool = advancesWithFingerMovingRight) -> [Tab] {
        advancesWithFingerMovingRight ? tabs.reversed() : tabs
    }

    /// Position als Tab-Index mit Nachkommastellen (1,5 = halb zwischen Rankings und Social) aus dem horizontalen
    /// Scroll-Versatz. Über die Enden hinaus (Gummiband) wird begrenzt.
    /// - Parameters:
    ///   - offset: Scroll-Versatz der Seitenleiste (0 = ganz links).
    ///   - pageWidth: Breite einer Seite.
    ///   - count: Anzahl der Tabs.
    public static func position(
        offset: CGFloat,
        pageWidth: CGFloat,
        count: Int,
        advancesWithFingerMovingRight: Bool = advancesWithFingerMovingRight
    ) -> Double? {
        guard pageWidth > 0, count > 0 else { return nil }
        let last = Double(count - 1)
        let visual = min(max(Double(offset / pageWidth), 0), last)
        return advancesWithFingerMovingRight ? last - visual : visual
    }

    /// Waagerechter Startpunkt der Scrollansicht (0 = ganz links, 1 = ganz rechts), damit sie beim ersten Anzeigen genau
    /// auf der Seite des gewählten Tabs steht – z. B. wenn ein Link die App direkt im Social-Tab öffnet.
    public static func initialAnchorX(index: Int, count: Int, advancesWithFingerMovingRight: Bool = advancesWithFingerMovingRight) -> Double {
        guard count > 1 else { return 0 }
        let clamped = Double(min(max(index, 0), count - 1))
        let visual = advancesWithFingerMovingRight ? Double(count - 1) - clamped : clamped
        return visual / Double(count - 1)
    }

    /// Ruhende Seite, wenn die Position (fast) ganzzahlig ist – sonst `nil` (Wischen oder Animation läuft).
    public static func settledIndex(_ position: Double, tolerance: Double = 0.002) -> Int? {
        let rounded = position.rounded()
        return abs(position - rounded) <= tolerance ? Int(rounded) : nil
    }

    /// Tabs, die bei dieser Position (teilweise) sichtbar sind – sie werden spätestens jetzt aufgebaut.
    public static func visibleIndices(_ position: Double, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let lower = min(max(Int(position.rounded(.down)), 0), count - 1)
        let upper = min(max(Int(position.rounded(.up)), 0), count - 1)
        return lower == upper ? [lower] : [lower, upper]
    }
}
