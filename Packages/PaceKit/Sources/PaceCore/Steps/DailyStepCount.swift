import Foundation

/// Die aggregierte Schrittzahl eines Kalendertags.
///
/// Bewusst nur ein Tageswert: Für Anzeige und spätere Rankings werden keine HealthKit-Rohdaten benötigt.
public struct DailyStepCount: Equatable, Sendable {
    /// Beginn des Kalendertags (lokale Zeitzone des Nutzers).
    public let day: Date
    /// Über alle Quellen deduplizierte Schrittsumme des Tags.
    public let steps: Int
    /// Zeitpunkt, zu dem der Wert gelesen wurde.
    public let updatedAt: Date

    public init(day: Date, steps: Int, updatedAt: Date) {
        self.day = day
        self.steps = steps
        self.updatedAt = updatedAt
    }
}
