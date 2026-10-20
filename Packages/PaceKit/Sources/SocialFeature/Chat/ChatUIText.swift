import Foundation
import PaceCore

/// Sichtbare Texte und VoiceOver-Beschriftungen der Chat-Ansichten (Deutsch, Englisch, Russisch).
///
/// Ohne SwiftUI, damit die Übersetzungen auch auf Linux geprüft werden. Alles als berechnete Werte, damit ein
/// Sprachwechsel sofort greift.
enum ChatUIText {
    private static func t(_ de: String, _ en: String, _ ru: String) -> String {
        PaceLocalization.text(de: de, en: en, ru: ru)
    }

    // MARK: Chatliste

    static var loadingChats: String { t("Chats werden geladen …", "Loading chats …", "Загружаем чаты …") }

    static var unavailableTitle: String { t("Chats", "Chats", "Чаты") }

    static func emptyTitle(_ filter: ChatListViewModel.Filter) -> String {
        switch filter {
        case .all: t("Noch keine Chats", "No chats yet", "Чатов пока нет")
        case .friends: t("Noch keine Privatchats", "No direct chats yet", "Личных чатов пока нет")
        case .groups: t("Noch keine Gruppenchats", "No group chats yet", "Групповых чатов пока нет")
        }
    }

    static func emptyMessage(_ filter: ChatListViewModel.Filter) -> String {
        switch filter {
        case .all:
            t(
                "Schreib einem Freund über sein Profil oder öffne den Chat einer Gruppe.",
                "Message a friend from their profile or open a group's chat.",
                "Напиши другу из его профиля или открой чат группы."
            )
        case .friends:
            t(
                "Öffne das Profil eines Freundes und tippe auf „Nachricht schreiben“.",
                "Open a friend's profile and tap “Write message”.",
                "Открой профиль друга и нажми «Написать сообщение»."
            )
        case .groups:
            t(
                "Jede Gruppe hat automatisch einen Chat für alle Mitglieder.",
                "Every group automatically has a chat for all its members.",
                "У каждой группы есть общий чат для всех участников."
            )
        }
    }

    static var filterLabel: String { t("Chats filtern", "Filter chats", "Фильтр чатов") }

    // MARK: Kopf

    static var groupDetails: String { t("Gruppendetails", "Group details", "Сведения о группе") }
    static var groupSettings: String { t("Gruppeneinstellungen", "Group settings", "Настройки группы") }
    static var viewProfile: String { t("Profil ansehen", "View profile", "Открыть профиль") }
    static var chatOptions: String { t("Chat-Optionen", "Chat options", "Настройки чата") }
    static var inviteMembers: String { t("Mitglieder einladen", "Invite members", "Пригласить участников") }
    static var showMembers: String { t("Mitglieder anzeigen", "Show members", "Показать участников") }
    static var reportPerson: String { t("Person melden", "Report person", "Пожаловаться на пользователя") }
    static var blockPerson: String { t("Person blockieren", "Block person", "Заблокировать") }

    static func streakAccessibility(title: String, status: String) -> String {
        title + ", " + status + ". " + t("Öffnet die Gruppendetails.", "Opens the group details.", "Открывает сведения о группе.")
    }

    // MARK: Verlauf

    static var emptyConversation: String {
        t("Noch keine Nachrichten. Schreib die erste!", "No messages yet. Write the first one!", "Сообщений пока нет. Напиши первым!")
    }

    static var loadingMessages: String { t("Nachrichten werden geladen …", "Loading messages …", "Загружаем сообщения …") }
    static var loadingOlder: String { t("Ältere Nachrichten werden geladen …", "Loading older messages …", "Загружаем более ранние сообщения …") }
    static var loadOlder: String { t("Ältere Nachrichten laden", "Load older messages", "Загрузить более ранние сообщения") }

    static var sending: String { t("Wird gesendet …", "Sending …", "Отправляется …") }
    static var uploading: String { t("Wird hochgeladen …", "Uploading …", "Загружается …") }
    static var notSent: String { t("Nicht gesendet", "Not sent", "Не отправлено") }
    static var sendAgain: String { t("Erneut senden", "Send again", "Отправить снова") }
    static var discard: String { t("Verwerfen", "Discard", "Удалить") }

    static var blockedMessage: String {
        t("Nachricht einer blockierten Person", "Message from a blocked person", "Сообщение заблокированного пользователя")
    }

    static var show: String { t("Anzeigen", "Show", "Показать") }
    static var you: String { t("Du", "You", "Вы") }

    static var sharedProfile: String { t("Geteiltes Profil", "Shared profile", "Профиль") }
    static var profileUnavailable: String {
        t("Dieses Profil ist nicht mehr verfügbar.", "This profile is no longer available.", "Этот профиль больше недоступен.")
    }
    static var gifBadge: String { "GIF" }
    static var tapToPlay: String { t("Zum Abspielen tippen", "Tap to play", "Нажми, чтобы воспроизвести") }
    static var imageUnavailable: String { t("Bild nicht verfügbar", "Image not available", "Изображение недоступно") }

    static func photo(from sender: String?) -> String {
        guard let sender else { return t("Dein Foto", "Your photo", "Твоё фото") }
        return t("Foto von \(sender)", "Photo from \(sender)", "Фото от \(sender)")
    }

    static func gif(from sender: String?) -> String {
        guard let sender else { return t("Dein GIF", "Your GIF", "Твой GIF") }
        return t("GIF von \(sender)", "GIF from \(sender)", "GIF от \(sender)")
    }

    static func sharedProfileAccessibility(name: String, username: String) -> String {
        t("Geteiltes Profil: \(name), @\(username)", "Shared profile: \(name), @\(username)", "Профиль: \(name), @\(username)")
    }

    static func messageAccessibility(sender: String?, content: String, time: String) -> String {
        let author = sender ?? you
        return "\(author): \(content), \(time)"
    }

    // MARK: Aktionen

    static var copy: String { t("Kopieren", "Copy", "Копировать") }
    static var reportMessage: String { t("Nachricht melden", "Report message", "Пожаловаться на сообщение") }
    static var delete: String { t("Löschen", "Delete", "Удалить") }
    static var deleteTitle: String { t("Nachricht löschen?", "Delete message?", "Удалить сообщение?") }

    static var deleteMessage: String {
        t(
            "Die Nachricht wird für alle in diesem Chat gelöscht.",
            "The message will be deleted for everyone in this chat.",
            "Сообщение будет удалено для всех в этом чате."
        )
    }

    // MARK: Eingabe

    static var placeholder: String { t("Nachricht schreiben", "Write a message", "Напиши сообщение") }
    static var send: String { t("Senden", "Send", "Отправить") }
    static var attach: String { t("Foto oder GIF senden", "Send a photo or GIF", "Отправить фото или GIF") }
    static var close: String { t("Schließen", "Close", "Закрыть") }

    /// Restzeichen unter dem Eingabefeld („Noch 120 Zeichen“ bzw. „5 Zeichen zu viel“).
    static func remaining(_ count: Int) -> String {
        if count >= 0 {
            return PaceLocalization.plural(
                count,
                de: ("Noch \(count.paceFormatted) Zeichen", "Noch \(count.paceFormatted) Zeichen"),
                en: ("\(count.paceFormatted) character left", "\(count.paceFormatted) characters left"),
                ru: ("Остался \(count.paceFormatted) символ", "Осталось \(count.paceFormatted) символа", "Осталось \(count.paceFormatted) символов")
            )
        }
        let over = -count
        return PaceLocalization.plural(
            over,
            de: ("\(over.paceFormatted) Zeichen zu viel", "\(over.paceFormatted) Zeichen zu viel"),
            en: ("\(over.paceFormatted) character too many", "\(over.paceFormatted) characters too many"),
            ru: ("Лишний \(over.paceFormatted) символ", "Лишних \(over.paceFormatted) символа", "Лишних \(over.paceFormatted) символов")
        )
    }
}
