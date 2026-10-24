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

    static var newMessages: String { t("Neue Nachrichten", "New messages", "Новые сообщения") }

    static var newMessagesHint: String { t("Springt zur neuesten Nachricht", "Jumps to the latest message", "Переход к последнему сообщению") }
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
    static var reply: String { t("Antworten", "Reply", "Ответить") }
    static var edit: String { t("Bearbeiten", "Edit", "Изменить") }
    static var favorite: String { t("Als Favorit speichern", "Save as favorite", "В избранное") }
    static var unfavorite: String { t("Favorit entfernen", "Remove favorite", "Убрать из избранного") }
    static var pin: String { t("Anpinnen", "Pin", "Закрепить") }
    static var unpin: String { t("Lösen", "Unpin", "Открепить") }
    static var edited: String { t("Bearbeitet", "Edited", "Изменено") }
    static var pinnedLabel: String { t("Angepinnt", "Pinned", "Закреплено") }
    static var favoriteLabel: String { t("Favorit", "Favorite", "Избранное") }
    static func replyingTo(_ name: String) -> String { t("Antwort auf \(name)", "Reply to \(name)", "Ответ \(name)") }
    static var editingMessage: String { t("Nachricht bearbeiten", "Edit message", "Изменить сообщение") }
    static var cancelReply: String { t("Antwort abbrechen", "Cancel reply", "Отменить ответ") }
    static var cancelEditing: String { t("Bearbeiten abbrechen", "Cancel editing", "Отменить изменение") }
    static var saveEdit: String { t("Änderung speichern", "Save change", "Сохранить изменение") }
    static var originalUnavailable: String { t("Nachricht nicht verfügbar", "Message unavailable", "Сообщение недоступно") }
    static var jumpToOriginal: String { t("Springt zur ursprünglichen Nachricht", "Jumps to the original message", "Переход к исходному сообщению") }
    static func pinnedBanner(_ index: Int, of count: Int) -> String {
        count > 1
            ? t("Angepinnt \(index) von \(count)", "Pinned \(index) of \(count)", "Закреплено \(index) из \(count)")
            : t("Angepinnte Nachricht", "Pinned message", "Закреплённое сообщение")
    }
    static var pinnedBannerHint: String { t("Springt zur Nachricht", "Jumps to the message", "Переход к сообщению") }
    static var favorites: String { t("Favoriten", "Favorites", "Избранное") }
    static var favoritesEmpty: String {
        t(
            "Noch keine Favoriten. Halte eine Nachricht gedrückt und wähle „Als Favorit speichern“. Nur du siehst deine Favoriten.",
            "No favorites yet. Press and hold a message and choose “Save as favorite”. Only you can see your favorites.",
            "Пока нет избранного. Удерживай сообщение и выбери «В избранное». Избранное видишь только ты."
        )
    }
    static var favoritesPrivacy: String {
        t("Nur du siehst deine Favoriten.", "Only you can see your favorites.", "Избранное видишь только ты.")
    }
    static var done: String { t("Fertig", "Done", "Готово") }
    static var voiceRecord: String { t("Sprachnachricht aufnehmen", "Record voice message", "Записать голосовое сообщение") }
    static var voiceRecordHint: String {
        t(
            "Gedrückt halten zum Aufnehmen, nach oben wischen zum Sperren, nach links zum Verwerfen.",
            "Hold to record, swipe up to lock, swipe left to discard.",
            "Удерживай для записи, смахни вверх, чтобы закрепить, влево — чтобы удалить."
        )
    }
    static var voiceHoldToRecord: String {
        t("Zum Aufnehmen gedrückt halten.", "Hold to record.", "Удерживай для записи.")
    }
    static var voiceMicrophoneDenied: String {
        t(
            "Pace darf das Mikrofon nicht nutzen. Du kannst es in den iOS-Einstellungen erlauben.",
            "Pace isn't allowed to use the microphone. You can allow it in iOS Settings.",
            "Pace не может использовать микрофон. Разреши это в настройках iOS."
        )
    }
    static var voicePlay: String { t("Abspielen", "Play", "Воспроизвести") }
    static var voicePause: String { t("Pause", "Pause", "Пауза") }
    static var voicePosition: String { t("Position", "Position", "Позиция") }
    static var voiceUnavailable: String {
        t("Sprachnachricht konnte nicht geladen werden.", "Voice message couldn't be loaded.", "Не удалось загрузить голосовое сообщение.")
    }
    static func voiceRecording(_ time: String) -> String { t("Aufnahme läuft, \(time)", "Recording, \(time)", "Идёт запись, \(time)") }
    static var voiceDiscard: String { t("Aufnahme verwerfen", "Discard recording", "Удалить запись") }
    static var voiceStop: String { t("Aufnahme beenden", "Stop recording", "Остановить запись") }
    static var voiceSend: String { t("Sprachnachricht senden", "Send voice message", "Отправить голосовое сообщение") }
    static var voiceSlideToCancel: String { t("Zum Verwerfen wischen", "Slide to cancel", "Смахни для отмены") }
    static var voiceLockHint: String { t("Nach oben wischen zum Sperren", "Swipe up to lock", "Смахни вверх, чтобы закрепить") }
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
