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
    /// Ersetzt alle geplanten Tagesziel-Erinnerungen durch `notifications` (siehe ``GoalReminderPlanner``).
    func scheduleGoalReminders(_ notifications: [PlannedNotification]) async
    /// Entfernt alle geplanten Erinnerungen an das Tagesziel (auch die älterer Versionen).
    func cancelGoalReminders() async
    /// Zeigt eine Mitteilung sofort (z. B. „Geschafft!“) – auch, während Pace geöffnet ist.
    func deliver(_ notification: PlannedNotification) async
}
