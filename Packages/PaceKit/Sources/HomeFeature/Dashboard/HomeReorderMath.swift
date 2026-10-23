import Foundation

/// Rechenregeln für das Umsortieren der Widgets per Ziehgriff – ohne SwiftUI, damit sie auf jeder Plattform testbar
/// sind.
///
/// Alle Rahmen liegen im Koordinatensystem des Scroll-Inhalts (unabhängig von der Scrollposition).
public enum HomeReorderMath {
    /// Höhe der Randzone, in der beim Ziehen automatisch gescrollt wird.
    public static let autoScrollEdge: CGFloat = 96
    /// Höchste Auto-Scroll-Geschwindigkeit in Punkten pro Sekunde (ganz am Rand).
    public static let maximumAutoScrollSpeed: CGFloat = 1_150

    /// Position, an der das gezogene Widget stehen soll: so viele andere Widgets davor, wie Mittelpunkte über der
    /// Mitte des gezogenen Widgets liegen.
    ///
    /// Nach einem Platztausch liegt die Mitte des übersprungenen Widgets auf der anderen Seite – die Position kippt
    /// deshalb nicht hin und her, auch wenn die Widgets unterschiedlich hoch sind.
    /// - Returns: Zielindex in der vollständigen Reihenfolge oder `nil`, wenn Rahmen fehlen.
    public static func targetIndex<ID: Hashable>(
        order: [ID],
        frames: [ID: CGRect],
        dragging: ID,
        draggedCenterY: CGFloat
    ) -> Int? {
        guard order.contains(dragging) else { return nil }
        var index = 0
        for id in order where id != dragging {
            guard let frame = frames[id] else { return nil }
            if frame.midY < draggedCenterY {
                index += 1
            }
        }
        return index
    }

    /// Auto-Scroll-Geschwindigkeit (Punkte pro Sekunde, negativ = nach oben) für die Fingerposition im sichtbaren
    /// Bereich. Außerhalb der Randzonen 0; zum Rand hin quadratisch schneller, damit es kontrollierbar bleibt.
    public static func autoScrollVelocity(
        fingerY: CGFloat,
        viewportHeight: CGFloat,
        edge: CGFloat = autoScrollEdge,
        maximumSpeed: CGFloat = maximumAutoScrollSpeed
    ) -> CGFloat {
        guard viewportHeight > 0, edge > 0 else { return 0 }
        let zone = min(edge, viewportHeight / 3)
        if fingerY < zone {
            let depth = min(1, (zone - fingerY) / zone)
            return -maximumSpeed * depth * depth
        }
        if fingerY > viewportHeight - zone {
            let depth = min(1, (fingerY - (viewportHeight - zone)) / zone)
            return maximumSpeed * depth * depth
        }
        return 0
    }

    /// Neuer Scroll-Versatz nach `delta`, begrenzt auf den scrollbaren Bereich.
    public static func clampedOffset(_ offset: CGFloat, delta: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(offset + delta, minimum), max(minimum, maximum))
    }
}
