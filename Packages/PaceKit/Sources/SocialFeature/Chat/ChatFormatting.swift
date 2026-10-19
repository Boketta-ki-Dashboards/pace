import Foundation
import PaceCore

/// Texte und Zeitangaben der Chats in der App-Sprache (Deutsch, Englisch, Russisch).
///
/// Bewusst ohne SwiftUI, damit Formate und Übersetzungen auch auf Linux getestet werden.
public enum ChatFormatting {
    // MARK: Zeit

    /// Uhrzeit einer Nachricht, z. B. `18:42` bzw. `6:42 PM`.
    public static func time(_ date: Date, calendar: ActivityCalendar) -> String {
        date.formatted(style(date: .omitted, time: .shortened, calendar: calendar))
    }

    /// Zeitpunkt der letzten Nachricht in der Chatliste: heute die Uhrzeit, dann „Gestern“, innerhalb der letzten
    /// Woche der Wochentag, sonst das Datum.
    public static func listTimestamp(_ date: Date, now: Date, calendar: ActivityCalendar) -> String {
        let day = calendar.day(containing: date)
        let today = calendar.day(containing: now)
        if day >= today {
            return time(date, calendar: calendar)
        }
        if day == calendar.adding(-1, to: today) {
            return yesterday
        }
        if day > calendar.adding(-7, to: today) {
            return weekday(date, calendar: calendar)
        }
        return date.formatted(style(date: .numeric, time: .omitted, calendar: calendar))
    }

    /// Trenner im Verlauf: „Heute“, „Gestern“, Wochentag (letzte Woche) oder Datum („12. Oktober“, mit Jahr, wenn es
    /// nicht das laufende ist).
    public static func dayTitle(_ day: LocalDate, today: LocalDate, calendar: ActivityCalendar) -> String {
        if day == today {
            return PaceLocalization.text(de: "Heute", en: "Today", ru: "Сегодня")
        }
        if day == calendar.adding(-1, to: today) {
            return yesterday
        }
        let date = calendar.startOfDay(day)
        if day < today, day > calendar.adding(-7, to: today) {
            return weekday(date, calendar: calendar)
        }
        var format = style(date: .omitted, time: .omitted, calendar: calendar).day().month(.wide)
        if day.year != today.year {
            format = format.year()
        }
        return date.formatted(format)
    }

    private static var yesterday: String {
        PaceLocalization.text(de: "Gestern", en: "Yesterday", ru: "Вчера")
    }

    /// Ausgeschriebener Wochentag mit großem Anfangsbuchstaben („Montag“, „Monday“, „Понедельник“).
    private static func weekday(_ date: Date, calendar: ActivityCalendar) -> String {
        let name = date.formatted(style(date: .omitted, time: .omitted, calendar: calendar).weekday(.wide))
        return name.prefix(1).uppercased(with: PaceLocalization.shared.locale) + name.dropFirst()
    }

    private static func style(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle, calendar: ActivityCalendar) -> Date.FormatStyle {
        Date.FormatStyle(
            date: date,
            time: time,
            locale: PaceLocalization.shared.locale,
            calendar: calendar.calendar,
            timeZone: calendar.timeZone
        )
    }

    // MARK: Chatliste

    /// Letzte Nachricht für die Chatliste: Text bzw. „Foto“, „GIF“, „Profil geteilt“; in Gruppen mit Absender
    /// („Mia: …“), eigene mit „Du: …“.
    public static func preview(for conversation: ConversationSummary) -> String {
        guard let last = conversation.lastMessage else {
            return conversation.kind == .group
                ? PaceLocalization.text(de: "Noch keine Nachrichten in der Gruppe", en: "No messages in the group yet", ru: "В группе пока нет сообщений")
                : PaceLocalization.text(de: "Noch keine Nachrichten", en: "No messages yet", ru: "Сообщений пока нет")
        }
        let body = content(kind: last.kind, text: last.text)
        if last.isOwn {
            return ownPrefix + ": " + body
        }
        if conversation.kind == .group {
            let sender = last.senderName ?? deletedAccount
            return sender + ": " + body
        }
        return body
    }

    /// Inhalt einer Nachricht in einer Zeile (Zeilenumbrüche werden zu Leerzeichen).
    public static func content(kind: ChatMessageKind, text: String?) -> String {
        switch kind {
        case .text:
            let words = (text ?? "").split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            return words.joined(separator: " ")
        case .image:
            return photo
        case .gif:
            return "GIF"
        case .profile:
            return PaceLocalization.text(de: "Profil geteilt", en: "Shared a profile", ru: "Поделился профилем")
        }
    }

    public static var photo: String {
        PaceLocalization.text(de: "Foto", en: "Photo", ru: "Фото")
    }

    /// „Du“ vor eigenen Nachrichten in der Chatliste.
    public static var ownPrefix: String {
        PaceLocalization.text(de: "Du", en: "You", ru: "Вы")
    }

    /// Absender, dessen Konto gelöscht wurde.
    public static var deletedAccount: String {
        PaceLocalization.text(de: "Gelöschtes Konto", en: "Deleted account", ru: "Удалённый аккаунт")
    }

    // MARK: Gruppen

    /// „12 Mitglieder“ / „12 members“ / „12 участников“.
    public static func members(_ count: Int) -> String {
        "\(count.paceFormatted) " + PaceLocalization.plural(
            count,
            de: ("Mitglied", "Mitglieder"),
            en: ("member", "members"),
            ru: ("участник", "участника", "участников")
        )
    }

    /// „12 Tage Streak“ / „12-day streak“ / „Серия: 12 дней“; ohne laufende Serie „Noch keine Streak“.
    public static func streakTitle(_ days: Int) -> String {
        guard days > 0 else {
            return PaceLocalization.text(de: "Noch keine Streak", en: "No streak yet", ru: "Серии пока нет")
        }
        return PaceLocalization.text(
            de: "\(PaceLocalization.days(days)) Streak",
            en: "\(days.paceFormatted)-day streak",
            ru: "Серия: \(PaceLocalization.days(days))"
        )
    }

    /// Stand des heutigen Gruppentags: „Flamme gesichert“ oder „Noch 2 Ziele heute“.
    public static func streakStatus(reached: Int, required: Int, complete: Bool) -> String {
        if complete {
            return PaceLocalization.text(de: "Flamme gesichert", en: "Flame secured", ru: "Пламя сохранено")
        }
        let missing = max(required - reached, 0)
        return PaceLocalization.plural(
            missing,
            de: ("Noch \(missing.paceFormatted) Ziel heute", "Noch \(missing.paceFormatted) Ziele heute"),
            en: ("\(missing.paceFormatted) more goal today", "\(missing.paceFormatted) more goals today"),
            ru: ("Сегодня ещё \(missing.paceFormatted) цель", "Сегодня ещё \(missing.paceFormatted) цели", "Сегодня ещё \(missing.paceFormatted) целей")
        )
    }

    // MARK: Zähler

    /// „3 ungelesene Nachrichten“ für VoiceOver.
    public static func unread(_ count: Int) -> String {
        PaceLocalization.plural(
            count,
            de: ("\(count.paceFormatted) ungelesene Nachricht", "\(count.paceFormatted) ungelesene Nachrichten"),
            en: ("\(count.paceFormatted) unread message", "\(count.paceFormatted) unread messages"),
            ru: ("\(count.paceFormatted) непрочитанное сообщение", "\(count.paceFormatted) непрочитанных сообщения", "\(count.paceFormatted) непрочитанных сообщений")
        )
    }
}
