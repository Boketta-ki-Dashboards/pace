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

    /// Abstand zwischen den Widgets aus ihren Rahmen (häufigster Abstand untereinander); ohne Messung `fallback`.
    public static func spacing(of frames: [CGRect], fallback: CGFloat) -> CGFloat {
        let sorted = frames.sorted { $0.minY < $1.minY }
        let gaps = zip(sorted, sorted.dropFirst()).map { ($1.minY - $0.maxY).rounded() }.filter { $0 >= 0 }
        guard !gaps.isEmpty else { return fallback }
        let counts = Dictionary(gaps.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key ?? fallback
    }

    /// Neuer Scroll-Versatz nach `delta`, begrenzt auf den scrollbaren Bereich.
    public static func clampedOffset(_ offset: CGFloat, delta: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(offset + delta, minimum), max(minimum, maximum))
    }
}

/// Aufbau der Widget-Liste während des Ziehens: Oberkante der Liste, Abstand und Höhe jedes Widgets.
///
/// Daraus ergibt sich der Platz jedes Widgets für jede Reihenfolge sofort – ohne auf neu gemessene Rahmen zu warten.
/// Gemessene Rahmen kommen erst nach dem Layout an; wer das gezogene Widget gegen einen solchen (veralteten) Rahmen
/// verschiebt, lässt es nach jedem Platztausch um die Höhe des übersprungenen Widgets springen.
public struct HomeReorderLayout<ID: Hashable>: Equatable {
    public var top: CGFloat
    public var spacing: CGFloat
    public var heights: [ID: CGFloat]

    public init(top: CGFloat, spacing: CGFloat, heights: [ID: CGFloat]) {
        self.top = top
        self.spacing = spacing
        self.heights = heights
    }

    /// Aus gemessenen Rahmen (Inhaltskoordinaten); `nil`, wenn ein Rahmen fehlt.
    public init?(order: [ID], frames: [ID: CGRect], fallbackSpacing: CGFloat) {
        let measured = order.compactMap { frames[$0] }
        guard measured.count == order.count, let top = measured.map(\.minY).min() else { return nil }
        self.init(
            top: top,
            spacing: HomeReorderMath.spacing(of: measured, fallback: fallbackSpacing),
            heights: Dictionary(uniqueKeysWithValues: zip(order, measured.map(\.height)))
        )
    }

    /// Rahmen aller Widgets (nur senkrecht aussagekräftig) in der Reihenfolge `order`.
    public func frames(order: [ID]) -> [ID: CGRect] {
        var result: [ID: CGRect] = [:]
        var y = top
        for id in order {
            let height = heights[id] ?? 0
            result[id] = CGRect(x: 0, y: y, width: 1, height: height)
            y += height + spacing
        }
        return result
    }

    /// Oberkante des Platzes von `id` in der Reihenfolge `order`.
    public func slotTop(of id: ID, order: [ID]) -> CGFloat? {
        frames(order: order)[id]?.minY
    }
}
