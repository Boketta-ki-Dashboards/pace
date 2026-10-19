import Foundation

/// Erlaubnis für Mitteilungen.
public enum NotificationAuthorization: Equatable, Sendable {
    /// Noch nicht gefragt.
    case notDetermined
    case authorized
    /// Abgelehnt – nur in den iOS-Einstellungen änderbar.
    case denied
}

/// Lokale Mitteilungen (ohne Server). Push-Mitteilungen für Nachrichten, Anfragen und Einladungen brauchen einen
/// Push-Dienst und sind noch nicht eingerichtet.
public protocol LocalNotificationScheduling: Sendable {
    func authorization() async -> NotificationAuthorization
    /// Fragt nach der Erlaubnis; `true`, wenn erlaubt.
    func requestAuthorization() async -> Bool
    /// Plant die Erinnerung an das Tagesziel für die nächsten Tage zur gewählten Uhrzeit. Ist das Ziel heute schon
    /// erreicht, beginnt sie morgen. Bestehende Erinnerungen werden ersetzt.
    func scheduleStreakReminders(hour: Int, minute: Int, skipToday: Bool, title: String, body: String) async
    /// Entfernt alle geplanten Erinnerungen an das Tagesziel.
    func cancelStreakReminders() async
}
