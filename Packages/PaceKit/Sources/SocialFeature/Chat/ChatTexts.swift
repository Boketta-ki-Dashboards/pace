import Foundation
import PaceCore

/// Hinweise und Zustände der Chats in drei Sprachen. Ohne SwiftUI, damit die ViewModels sie testbar verwenden.
enum ChatTexts {
    static func message(for error: any Error) -> String {
        if let error = error as? SocialError {
            return error.message
        }
        if let error = error as? MediaError {
            return media(error)
        }
        return SocialError.unexpected("").message
    }

    static func media(_ error: MediaError) -> String {
        switch error {
        case .tooLarge:
            PaceLocalization.text(
                de: "Das Bild ist zu groß (höchstens 10 MB).",
                en: "The image is too large (10 MB at most).",
                ru: "Изображение слишком большое (не более 10 МБ)."
            )
        case .unsupportedType:
            PaceLocalization.text(
                de: "Dieses Format wird nicht unterstützt. Möglich sind Fotos (JPEG, PNG, HEIC, WebP) und GIFs.",
                en: "This format isn't supported. You can send photos (JPEG, PNG, HEIC, WebP) and GIFs.",
                ru: "Этот формат не поддерживается. Можно отправлять фото (JPEG, PNG, HEIC, WebP) и GIF."
            )
        case .notAllowed:
            PaceLocalization.text(
                de: "Du kannst in diesem Chat keine Bilder senden.",
                en: "You can't send images in this chat.",
                ru: "В этом чате нельзя отправлять изображения."
            )
        case .notFound:
            PaceLocalization.text(de: "Das Bild ist nicht mehr verfügbar.", en: "The image is no longer available.", ru: "Изображение больше недоступно.")
        case .network:
            SocialError.network.message
        case .unavailable:
            mediaUnavailable
        case .unexpected:
            SocialError.unexpected("").message
        }
    }

    static var unavailable: String {
        PaceLocalization.text(
            de: "Chats sind ohne Verbindung zum Pace-Server nicht verfügbar.",
            en: "Chats aren't available without a connection to the Pace server.",
            ru: "Чаты недоступны без подключения к серверу Pace."
        )
    }

    static var mediaUnavailable: String {
        PaceLocalization.text(
            de: "Bilder und GIFs sind auf dem Server noch nicht eingerichtet.",
            en: "Images and GIFs are not set up on the server yet.",
            ru: "Изображения и GIF ещё не настроены на сервере."
        )
    }

    static var mediaSelectionFailed: String {
        PaceLocalization.text(
            de: "Das Bild konnte nicht geladen werden. Bitte wähle es erneut aus.",
            en: "The image couldn't be loaded. Please select it again.",
            ru: "Не удалось загрузить изображение. Выбери его ещё раз."
        )
    }

    static var conversationGone: String {
        PaceLocalization.text(
            de: "Diesen Chat gibt es nicht mehr oder du hast keinen Zugriff mehr darauf.",
            en: "This chat no longer exists or you no longer have access to it.",
            ru: "Этого чата больше нет, или у тебя больше нет к нему доступа."
        )
    }

    static var reported: String {
        PaceLocalization.text(
            de: "Danke für deine Meldung. Das Pace-Team sieht sie sich an.",
            en: "Thanks for your report. The Pace team will review it.",
            ru: "Спасибо за жалобу. Команда Pace её рассмотрит."
        )
    }

    static func blocked(_ name: String) -> String {
        PaceLocalization.text(
            de: "Du hast \(name) blockiert.",
            en: "You blocked \(name).",
            ru: "Пользователь \(name) заблокирован."
        )
    }

    static var messageDeleted: String {
        PaceLocalization.text(de: "Nachricht gelöscht.", en: "Message deleted.", ru: "Сообщение удалено.")
    }

    static var tooLong: String {
        SocialError.invalidMessage.message
    }

    static var olderFailed: String {
        PaceLocalization.text(
            de: "Ältere Nachrichten konnten nicht geladen werden.",
            en: "Older messages couldn't be loaded.",
            ru: "Не удалось загрузить более ранние сообщения."
        )
    }

    /// Erklärung, wenn in einer Unterhaltung nicht mehr geschrieben werden kann.
    static func readOnly(kind: ConversationKind, peerName: String?, blockedByMe: Bool) -> String {
        switch kind {
        case .group:
            return PaceLocalization.text(
                de: "Du bist kein Mitglied dieser Gruppe mehr und kannst hier nicht mehr schreiben.",
                en: "You're no longer a member of this group and can't write here anymore.",
                ru: "Ты больше не участник этой группы и не можешь здесь писать."
            )
        case .direct:
            if blockedByMe, let peerName {
                return PaceLocalization.text(
                    de: "Du hast \(peerName) blockiert. Ihr könnt euch keine Nachrichten mehr schreiben.",
                    en: "You blocked \(peerName). You can no longer message each other.",
                    ru: "Пользователь \(peerName) заблокирован. Вы больше не можете писать друг другу."
                )
            }
            return PaceLocalization.text(
                de: "Ihr seid nicht mehr befreundet oder eine Blockierung besteht. Neue Nachrichten sind nicht möglich.",
                en: "You're no longer friends or one of you blocked the other. New messages aren't possible.",
                ru: "Вы больше не друзья, или кто-то из вас заблокировал другого. Новые сообщения невозможны."
            )
        }
    }
}

/// Rückmeldung einer Aktion im Chat (Erfolg oder Fehler).
public struct ChatNotice: Equatable, Sendable {
    public let text: String
    public let isError: Bool

    public init(text: String, isError: Bool) {
        self.text = text
        self.isError = isError
    }
}

/// Teilen eines Profils ist bei einzelnen Empfängern fehlgeschlagen; bei den anderen wurde es gesendet.
public struct ProfileShareError: Error, Equatable, Sendable {
    public struct Failure: Equatable, Sendable {
        public let target: ChatTarget
        public let message: String

        public init(target: ChatTarget, message: String) {
            self.target = target
            self.message = message
        }
    }

    public let failures: [Failure]
    /// Anzahl der Empfänger, an die das Profil gesendet wurde.
    public let sharedCount: Int

    public init(failures: [Failure], sharedCount: Int) {
        self.failures = failures
        self.sharedCount = sharedCount
    }

    /// z. B. „An Mia gesendet. Nicht gesendet an: Klasse 8b (Keine Verbindung …)“.
    public var message: String {
        let failed = failures.map { "\($0.target.title) (\($0.message))" }.joined(separator: ", ")
        let notSent = PaceLocalization.text(de: "Nicht gesendet an: \(failed)", en: "Not sent to: \(failed)", ru: "Не отправлено: \(failed)")
        guard sharedCount > 0 else { return notSent }
        let sent = PaceLocalization.plural(
            sharedCount,
            de: ("An \(sharedCount.paceFormatted) Chat gesendet.", "An \(sharedCount.paceFormatted) Chats gesendet."),
            en: ("Sent to \(sharedCount.paceFormatted) chat.", "Sent to \(sharedCount.paceFormatted) chats."),
            ru: ("Отправлено в \(sharedCount.paceFormatted) чат.", "Отправлено в \(sharedCount.paceFormatted) чата.", "Отправлено в \(sharedCount.paceFormatted) чатов.")
        )
        return sent + " " + notSent
    }
}

extension ConversationSummary {
    /// Kopie mit geändertem Ungelesen-Zähler bzw. Schreibrecht (z. B. nach dem Lesen oder einer Blockierung).
    func replacing(unreadCount: Int? = nil, canSend: Bool? = nil) -> ConversationSummary {
        ConversationSummary(
            id: id,
            kind: kind,
            title: title,
            peer: peer,
            groupID: groupID,
            groupImagePath: groupImagePath,
            memberCount: memberCount,
            lastMessage: lastMessage,
            unreadCount: unreadCount ?? self.unreadCount,
            canSend: canSend ?? self.canSend,
            updatedAt: updatedAt
        )
    }
}
