import Foundation
import PaceCore
import UserNotifications

/// Lokale Mitteilungen über `UNUserNotificationCenter`: Tagesziel-Erinnerungen (im Voraus geplant, siehe
/// ``GoalReminderPlanner``) und sofortige Mitteilungen wie „Geschafft!“. Mitteilungen erscheinen auch, während Pace
/// geöffnet ist (als Banner).
///
/// Push-Mitteilungen bei geschlossener App (z. B. neue Chatnachrichten) bräuchten APNs mit einer Push-Capability und
/// einem Server-Versand – das ist nicht eingerichtet (mit einem kostenlosen Personal Team auch nicht möglich).
public struct UserNotificationScheduler: LocalNotificationScheduling {
    /// Kennung der Erinnerungen älterer Versionen (eine Uhrzeit) – werden beim Neuplanen entfernt.
    private static let legacyIdentifierPrefix = "pace.streak-reminder."

    public init() {
        ForegroundNotificationPresenter.activate()
    }

    public func authorization() async -> NotificationAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .authorized
        }
    }

    public func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    public func scheduleGoalReminders(_ notifications: [PlannedNotification]) async {
        let center = UNUserNotificationCenter.current()
        await cancelGoalReminders()
        for notification in notifications {
            let trigger = UNCalendarNotificationTrigger(dateMatching: notification.dateComponents, repeats: false)
            let request = UNNotificationRequest(identifier: notification.identifier, content: content(notification), trigger: trigger)
            try? await center.add(request)
        }
    }

    public func cancelGoalReminders() async {
        let center = UNUserNotificationCenter.current()
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(GoalReminderPlanner.identifierPrefix) || $0.hasPrefix(Self.legacyIdentifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func deliver(_ notification: PlannedNotification) async {
        let request = UNNotificationRequest(identifier: notification.identifier, content: content(notification), trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func content(_ notification: PlannedNotification) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        return content
    }
}

/// Zeigt Mitteilungen von Pace auch an, während die App im Vordergrund ist (sonst unterdrückt iOS sie).
final class ForegroundNotificationPresenter: NSObject, @unchecked Sendable {
    private static let shared = ForegroundNotificationPresenter()

    static func activate() {
        let center = UNUserNotificationCenter.current()
        if center.delegate !== shared {
            center.delegate = shared
        }
    }
}

extension ForegroundNotificationPresenter: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
