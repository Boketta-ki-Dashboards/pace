import Foundation

/// Rechenregeln für das Wischen zwischen den Haupttabs (Home – Rankings – Social – Profil), ohne SwiftUI.
///
/// Richtung (verbindlich laut Auftrag 4; die umgekehrte Richtung aus Auftrag 3 ist aufgehoben): normales Paging. Die
/// Seiten liegen von links nach rechts in Tab-Reihenfolge und folgen dem Finger.
/// - Finger von rechts nach links → der nächste Tab rechts kommt von rechts herein (Home → Rankings → Social → Profil).
/// - Finger von links nach rechts → der vorherige Tab links (Profil → Social → Rankings → Home).
/// - An Home und Profil endet die Reihe (Gummiband, keine Schleife).
public enum PaceTabPaging {
    /// Position als Tab-Index mit Nachkommastellen (1,5 = halb zwischen Rankings und Social) aus dem horizontalen
    /// Scroll-Versatz. Über die Enden hinaus (Gummiband) wird begrenzt.
    /// - Parameters:
    ///   - offset: Scroll-Versatz der Seitenleiste (0 = ganz links = Home).
    ///   - pageWidth: Breite einer Seite.
    ///   - count: Anzahl der Tabs.
    public static func position(offset: CGFloat, pageWidth: CGFloat, count: Int) -> Double? {
        guard pageWidth > 0, count > 0 else { return nil }
        return min(max(Double(offset / pageWidth), 0), Double(count - 1))
    }

    /// Position während einer Wischbewegung: Die Seiten folgen dem Finger, der Scroll-Versatz ändert sich also
    /// entgegengesetzt zur Fingerbewegung (Finger nach links = negative Verschiebung = größerer Versatz = weiter rechts
    /// in der Tab-Reihenfolge).
    /// - Parameters:
    ///   - index: Ausgangs-Tab.
    ///   - fingerTranslation: Waagerechte Fingerbewegung seit Beginn (negativ = nach links).
    public static func position(from index: Int, fingerTranslation: CGFloat, pageWidth: CGFloat, count: Int) -> Double? {
        guard pageWidth > 0, count > 0 else { return nil }
        let start = CGFloat(min(max(index, 0), count - 1)) * pageWidth
        return position(offset: start - fingerTranslation, pageWidth: pageWidth, count: count)
    }

    /// Waagerechter Startpunkt der Scrollansicht (0 = ganz links, 1 = ganz rechts), damit sie beim ersten Anzeigen genau
    /// auf der Seite des gewählten Tabs steht – z. B. wenn ein Link die App direkt im Social-Tab öffnet.
    public static func initialAnchorX(index: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        return Double(min(max(index, 0), count - 1)) / Double(count - 1)
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
