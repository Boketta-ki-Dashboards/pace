import Foundation
import PaceCore
import UserNotifications

/// Lokale Mitteilungen über `UNUserNotificationCenter`. Plant die Erinnerung an das Tagesziel als einzelne Mitteilungen
/// für die nächsten 14 Tage – so lässt sich der heutige Tag auslassen, sobald das Ziel erreicht ist.
public struct UserNotificationScheduler: LocalNotificationScheduling {
    private static let identifierPrefix = "pace.streak-reminder."
    private static let daysAhead = 14

    public init() {}

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

    public func scheduleStreakReminders(hour: Int, minute: Int, skipToday: Bool, title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        await cancelStreakReminders()
        let calendar = Calendar.current
        let now = Date()
        for offset in 0..<Self.daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            guard let fireDate = calendar.date(from: components), fireDate > now else { continue }
            if offset == 0, skipToday { continue }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: Self.identifierPrefix + "\(offset)", content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    public func cancelStreakReminders() async {
        let center = UNUserNotificationCenter.current()
        let identifiers = (0..<Self.daysAhead).map { Self.identifierPrefix + "\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
