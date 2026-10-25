import Foundation

/// Schritt beim Wischen durch Zeiträume (Statistik, Kalender, Flammenkalender).
public enum PaceSwipeStep: Equatable, Sendable {
    case previous
    case next
}

/// Rechenregeln für das Wischen durch Tage, Wochen und Monate, ohne SwiftUI.
///
/// Richtung wie beim üblichen Kalender-Paging: Finger nach rechts → vorheriger Zeitraum, Finger nach links → nächster.
/// Nur eindeutig waagerechte Bewegungen zählen, damit senkrechtes Scrollen der Seite nie einen Wechsel auslöst.
public enum PaceSwipeNavigation {
    /// Ab dieser Strecke beginnt die Geste (kleinere Bewegungen bleiben Tippen bzw. Scrollen).
    public static let minimumDistance: CGFloat = 24
    /// Mindeststrecke für einen Wechsel beim langsamen Ziehen.
    public static let commitDistance: CGFloat = 60
    /// Mindeststrecke der vorhergesagten Endposition für einen Wechsel bei schnellem Wischen.
    public static let flickDistance: CGFloat = 140
    /// Waagerecht heißt: mindestens so viel mal breiter als hoch.
    public static let horizontalDominance: CGFloat = 1.5
    /// Widerstand, solange der Finger in eine Richtung zieht, in der es nicht weitergeht (z. B. nach heute).
    public static let resistance: CGFloat = 0.25
    /// Größte sichtbare Verschiebung des Inhalts während des Ziehens.
    public static let maximumOffset: CGFloat = 90

    /// Breite des Streifens am linken Bildschirmrand, der der Zurück-Geste von iOS gehört: Dort beginnende Bewegungen
    /// wechseln nie den Zeitraum (sonst schöbe das Zurückwischen zugleich das Diagramm oder wechselte den Zeitraum).
    public static let backSwipeEdgeWidth: CGFloat = 28

    /// Ob eine Bewegung, die bei `startX` (Punkte vom linken Bildschirmrand) beginnt, der Zurück-Geste gehört.
    public static func belongsToBackSwipe(startX: CGFloat) -> Bool {
        startX <= backSwipeEdgeWidth
    }

    /// Ob eine Bewegung als waagerechtes Wischen gilt.
    public static func isHorizontal(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height) * horizontalDominance
    }

    /// Wechsel beim Loslassen – oder `nil` (zu kurz, eher senkrecht oder in dieser Richtung geht es nicht weiter).
    /// - Parameters:
    ///   - translation: Fingerbewegung seit Beginn (Breite negativ = nach links).
    ///   - predictedEndTranslation: Vom System vorhergesagte Endposition (berücksichtigt die Geschwindigkeit).
    public static func step(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        canShowPrevious: Bool,
        canShowNext: Bool
    ) -> PaceSwipeStep? {
        guard isHorizontal(translation) else { return nil }
        let width = translation.width
        let predicted = predictedEndTranslation.width
        // Zurückgezogen: Die vorhergesagte Bewegung zeigt in die Gegenrichtung – kein Wechsel.
        guard width.sign == predicted.sign || predicted == 0 else { return nil }
        let isFarEnough = abs(width) >= commitDistance || abs(predicted) >= flickDistance
        guard isFarEnough else { return nil }
        if width > 0 {
            return canShowPrevious ? .previous : nil
        }
        return canShowNext ? .next : nil
    }

    /// Sichtbare Verschiebung des Inhalts während des Ziehens: folgt dem Finger gedämpft; in eine Richtung ohne
    /// weiteren Zeitraum nur mit starkem Widerstand (Gummiband), nie über ``maximumOffset`` hinaus.
    public static func dragOffset(translation: CGSize, canShowPrevious: Bool, canShowNext: Bool) -> CGFloat {
        guard isHorizontal(translation) else { return 0 }
        let width = translation.width
        let canMove = width > 0 ? canShowPrevious : canShowNext
        let damped = width * (canMove ? 0.5 : resistance)
        return min(max(damped, -maximumOffset), maximumOffset)
    }

    /// Von welcher Seite der neue Zeitraum hereingleitet: der vorherige von links (negativ), der nächste von rechts.
    public static func entryOffset(for step: PaceSwipeStep, distance: CGFloat = 36) -> CGFloat {
        step == .previous ? -distance : distance
    }
}
