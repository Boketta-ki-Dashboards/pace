import Foundation
import PaceCore

/// Alle festen Texte des Social-Bereichs (ohne Chats) in Deutsch, Englisch und Russisch.
///
/// Berechnete Eigenschaften statt Konstanten: Die Sprache kann sich zur Laufzeit ändern, Views lesen die Texte beim
/// Zeichnen neu. Nutzernamen und Gruppennamen werden nie übersetzt.
enum SocialText {
    private static func t(_ de: String, _ en: String, _ ru: String) -> String {
        PaceLocalization.text(de: de, en: en, ru: ru)
    }

    // MARK: Allgemein

    static var social: String { t("Social", "Social", "Друзья") }
    static var cancel: String { t("Abbrechen", "Cancel", "Отмена") }
    static var retry: String { t("Erneut versuchen", "Try again", "Попробовать снова") }
    static var save: String { t("Speichern", "Save", "Сохранить") }
    static var closeNotice: String { t("Hinweis schließen", "Dismiss notice", "Закрыть уведомление") }
    static var settings: String { t("Einstellungen", "Settings", "Настройки") }
    static var friends: String { t("Freunde", "Friends", "Друзья") }
    static var groups: String { t("Gruppen", "Groups", "Группы") }
    static var chats: String { t("Chats", "Chats", "Чаты") }
    static var today: String { t("Heute", "Today", "Сегодня") }
    static var thisWeek: String { t("Diese Woche", "This week", "На этой неделе") }
    static var competitionSteps: String { t("Wettbewerbsschritte", "Competition steps", "Шаги для рейтинга") }
    static var you: String { t("DU", "YOU", "ТЫ") }
    static var loading: String { t("Freunde und Gruppen werden geladen …", "Loading friends and groups …", "Загружаем друзей и группы …") }
    static var regionalRankingsIndependent: String {
        t(
            "Deine regionalen Rankings funktionieren unabhängig davon.",
            "Your regional rankings work independently of this.",
            "Твои региональные рейтинги работают независимо от этого."
        )
    }

    static var featureUnavailable: String {
        t(
            "Diese Funktion ist auf dem Server noch nicht eingerichtet.",
            "This feature isn't set up on the server yet.",
            "Эта функция ещё не настроена на сервере."
        )
    }

    static func members(_ count: Int) -> String {
        "\(count.paceFormatted) " + PaceLocalization.plural(
            count,
            de: ("Mitglied", "Mitglieder"),
            en: ("member", "members"),
            ru: ("участник", "участника", "участников")
        )
    }

    static func sectionCount(_ title: String, _ count: Int) -> String {
        "\(title) · \(count.paceFormatted)"
    }

    // MARK: Hauptseite

    static var addFriend: String { t("Freund hinzufügen", "Add friend", "Добавить друга") }
    static var createGroup: String { t("Gruppe erstellen", "Create group", "Создать группу") }
    static var searchFriendsAndChats: String { t("Freunde und Chats suchen", "Search friends and chats", "Поиск друзей и чатов") }
    static var topFriends: String { t("Top-Freunde", "Top friends", "Топ друзей") }
    static var seeAll: String { t("Alle ansehen", "See all", "Смотреть все") }
    static var friendRequests: String { t("Freundschaftsanfragen", "Friend requests", "Заявки в друзья") }
    static var myGroups: String { t("Meine Gruppen", "My groups", "Мои группы") }
    static var socialSettings: String { t("Social-Einstellungen", "Social settings", "Настройки общения") }
    static var friendsAndGroups: String { t("Freunde und Gruppen", "Friends and groups", "Друзья и группы") }
    static var noFriendsYet: String {
        t(
            "Noch keine Freunde – füge jemanden über „Freund hinzufügen“ hinzu.",
            "No friends yet – add someone with “Add friend”.",
            "Пока нет друзей – добавь кого-нибудь через «Добавить друга»."
        )
    }

    static func noMatches(_ query: String) -> String {
        t("Keine Treffer für „\(query)“.", "No results for “\(query)”.", "Ничего не найдено по запросу «\(query)».")
    }

    static func openRequests(_ count: Int) -> String {
        PaceLocalization.plural(
            count,
            de: ("\(count) offene Anfrage", "\(count) offene Anfragen"),
            en: ("\(count) open request", "\(count) open requests"),
            ru: ("\(count) открытая заявка", "\(count) открытые заявки", "\(count) открытых заявок")
        )
    }

    static func openInvitations(_ count: Int) -> String {
        PaceLocalization.plural(
            count,
            de: ("\(count) Einladung", "\(count) Einladungen"),
            en: ("\(count) invitation", "\(count) invitations"),
            ru: ("\(count) приглашение", "\(count) приглашения", "\(count) приглашений")
        )
    }

    static func groupCount(_ count: Int) -> String {
        PaceLocalization.plural(
            count,
            de: ("\(count) Gruppe", "\(count) Gruppen"),
            en: ("\(count) group", "\(count) groups"),
            ru: ("\(count) группа", "\(count) группы", "\(count) групп")
        )
    }

    // MARK: Freund hinzufügen

    static var searchResults: String { t("Suchergebnisse", "Search results", "Результаты поиска") }
    static var searchUsername: String { t("Benutzername suchen", "Search username", "Поиск по имени пользователя") }
    static var searching: String { t("Suche läuft …", "Searching …", "Идёт поиск …") }
    static var searchHint: String {
        t(
            "Suche nach einem Benutzernamen – mindestens 3 Zeichen.",
            "Search for a username – at least 3 characters.",
            "Введи имя пользователя – не менее 3 символов."
        )
    }

    static func nobodyStartsWith(_ query: String) -> String {
        t(
            "Niemand gefunden, dessen Benutzername mit „\(query)“ beginnt.",
            "No one found whose username starts with “\(query)”.",
            "Не найдено пользователей, чьё имя начинается с «\(query)»."
        )
    }

    static var add: String { t("Hinzufügen", "Add", "Добавить") }
    static var requestSent: String { t("Anfrage gesendet", "Request sent", "Заявка отправлена") }
    static var alreadyFriends: String { t("Bereits befreundet", "Already friends", "Уже в друзьях") }
    static var accept: String { t("Annehmen", "Accept", "Принять") }
    static var decline: String { t("Ablehnen", "Decline", "Отклонить") }
    static var thatsYou: String { t("Das bist du", "That's you", "Это ты") }
    static var shareProfile: String { t("Profil teilen", "Share profile", "Поделиться профилем") }
    static var writeMessage: String { t("Nachricht schreiben", "Write message", "Написать сообщение") }
    static var blockUser: String { t("Nutzer blockieren", "Block user", "Заблокировать") }
    static var moreActions: String { t("Weitere Aktionen", "More actions", "Другие действия") }

    static func moreActions(for name: String) -> String {
        t("Weitere Aktionen für \(name)", "More actions for \(name)", "Другие действия: \(name)")
    }

    // MARK: Anfragen

    static var incoming: String { t("Eingegangen", "Received", "Входящие") }
    static var sent: String { t("Gesendet", "Sent", "Отправленные") }
    static var pending: String { t("Ausstehend", "Pending", "Ожидает") }
    static var withdraw: String { t("Zurückziehen", "Withdraw", "Отозвать") }
    static var noIncomingRequests: String { t("Keine neuen Anfragen.", "No new requests.", "Новых заявок нет.") }
    static var noRequestsTitle: String { t("Keine offenen Anfragen", "No open requests", "Нет открытых заявок") }
    static var noRequestsMessage: String {
        t(
            "Sobald dir jemand eine Freundschaftsanfrage schickt oder du eine sendest, erscheint sie hier.",
            "As soon as someone sends you a friend request or you send one, it appears here.",
            "Как только кто-то отправит тебе заявку в друзья или ты отправишь её сам, она появится здесь."
        )
    }

    static func acceptRequest(from name: String) -> String {
        t("Anfrage von \(name) annehmen", "Accept request from \(name)", "Принять заявку от \(name)")
    }

    static func declineRequest(from name: String) -> String {
        t("Anfrage von \(name) ablehnen", "Decline request from \(name)", "Отклонить заявку от \(name)")
    }

    static func withdrawRequest(to name: String) -> String {
        t("Anfrage an \(name) zurückziehen", "Withdraw request to \(name)", "Отозвать заявку для \(name)")
    }

    // MARK: Rückmeldungen

    static func requestSent(to name: String) -> String {
        t("Anfrage an \(name) gesendet.", "Friend request sent to \(name).", "Заявка отправлена: \(name).")
    }

    static func nowFriends(with name: String) -> String {
        t("Du und \(name) seid jetzt befreundet.", "You and \(name) are now friends.", "Теперь вы с \(name) друзья.")
    }

    static var alreadyFriendsNotice: String { t("Ihr seid bereits befreundet.", "You're already friends.", "Вы уже друзья.") }
    static var alreadyRequestedNotice: String {
        t("Du hast bereits eine Anfrage gesendet.", "You've already sent a request.", "Заявка уже отправлена.")
    }

    static var requestDeclined: String { t("Anfrage abgelehnt.", "Request declined.", "Заявка отклонена.") }
    static var requestWithdrawn: String { t("Anfrage zurückgezogen.", "Request withdrawn.", "Заявка отозвана.") }

    static func friendRemoved(_ name: String) -> String {
        t(
            "\(name) ist nicht mehr in deinen Freunden.",
            "\(name) is no longer your friend.",
            "\(name) больше нет среди твоих друзей."
        )
    }

    static func joinedGroup(_ name: String) -> String {
        t("Du bist „\(name)“ beigetreten.", "You joined “\(name)”.", "Теперь ты в группе «\(name)».")
    }

    static var invitationDeclined: String { t("Einladung abgelehnt.", "Invitation declined.", "Приглашение отклонено.") }

    static func groupCreated(_ name: String) -> String {
        t("Gruppe „\(name)“ erstellt.", "Group “\(name)” created.", "Группа «\(name)» создана.")
    }

    static func blocked(_ name: String) -> String {
        t("\(name) ist blockiert.", "\(name) is blocked.", "Пользователь \(name) заблокирован.")
    }

    static func unblocked(_ name: String) -> String {
        t("Blockierung von \(name) aufgehoben.", "\(name) is unblocked.", "Пользователь \(name) разблокирован.")
    }

    static var reportSent: String {
        t("Danke! Deine Meldung wurde gesendet.", "Thanks! Your report has been sent.", "Спасибо! Жалоба отправлена.")
    }

    static var profileShared: String { t("Profil geteilt.", "Profile shared.", "Профиль отправлен.") }

    static var invitesIncomplete: String {
        t(
            "Nicht alle Einladungen konnten verschickt werden – du kannst sie unter „Mitglieder“ erneut senden.",
            "Not all invitations could be sent – you can send them again under “Members”.",
            "Не все приглашения удалось отправить – их можно отправить снова в разделе «Участники»."
        )
    }

    static var privacyNotSaved: String {
        t(
            "Die gewählte Privatsphäre konnte nicht gespeichert werden. Prüfe sie in den Gruppeneinstellungen.",
            "The chosen privacy couldn't be saved. Check it in the group settings.",
            "Не удалось сохранить выбранную конфиденциальность. Проверь её в настройках группы."
        )
    }

    static var imageNotSaved: String {
        t(
            "Das Gruppenbild konnte nicht gespeichert werden. Du kannst es in den Einstellungen erneut auswählen.",
            "The group photo couldn't be saved. You can choose it again in the settings.",
            "Не удалось сохранить фото группы. Его можно выбрать снова в настройках."
        )
    }

    static func profileLinkNotFound(_ username: String) -> String {
        t(
            "Das Profil @\(username) gibt es nicht oder es ist nicht sichtbar.",
            "The profile @\(username) doesn't exist or isn't visible.",
            "Профиль @\(username) не существует или скрыт."
        )
    }

    // MARK: Profil

    static var profile: String { t("Profil", "Profile", "Профиль") }
    static var removeFriend: String { t("Freund entfernen", "Remove friend", "Удалить из друзей") }
    static var unblock: String { t("Blockierung aufheben", "Unblock", "Разблокировать") }
    static var stepsOnlyForFriends: String {
        t("Nur Freunde sehen die Schritte des anderen.", "Only friends see each other's steps.", "Шаги видят только друзья.")
    }

    static var blockedByMe: String { t("Du hast diese Person blockiert.", "You blocked this person.", "Этот человек заблокирован.") }
    static var profileNotFoundTitle: String { t("Profil nicht gefunden", "Profile not found", "Профиль не найден") }
    static var profileNotFoundMessage: String {
        t(
            "Das Profil gibt es nicht oder es ist nicht sichtbar.",
            "This profile doesn't exist or isn't visible.",
            "Профиль не существует или скрыт."
        )
    }

    static var incomingRequest: String { t("Möchte mit dir befreundet sein", "Wants to be friends", "Хочет добавить тебя в друзья") }

    static func friendsSince(_ date: Date) -> String {
        let formatted = date.formatted(.dateTime.day().month(.abbreviated).year().locale(PaceLocalization.shared.locale))
        return t("Befreundet seit \(formatted)", "Friends since \(formatted)", "Друзья с \(formatted)")
    }

    static func blockTitle(_ name: String) -> String {
        t("\(name) blockieren?", "Block \(name)?", "Заблокировать \(name)?")
    }

    static var blockMessage: String {
        t(
            "Eure Freundschaft, offene Anfragen und Einladungen enden. Ihr findet euch nicht mehr in der Suche und könnt euch keine Nachrichten mehr schreiben.",
            "Your friendship, open requests and invitations will end. You won't find each other in search and can't message each other.",
            "Дружба, открытые заявки и приглашения будут отменены. Вы не сможете найти друг друга в поиске и писать друг другу."
        )
    }

    static func removeFriendTitle(_ name: String) -> String {
        t("\(name) entfernen?", "Remove \(name)?", "Удалить \(name) из друзей?")
    }

    static var removeFriendMessage: String {
        t(
            "Ihr seht danach eure Schritte nicht mehr. Offene Gruppeneinladungen zwischen euch werden zurückgezogen.",
            "You will no longer see each other's steps. Open group invitations between you will be withdrawn.",
            "Вы больше не будете видеть шаги друг друга. Открытые приглашения в группы между вами будут отозваны."
        )
    }

    static func shareProfileText(username: String, isOwn: Bool) -> String {
        isOwn
            ? t("Füge mich bei Pace hinzu: @\(username)", "Add me on Pace: @\(username)", "Добавь меня в Pace: @\(username)")
            : t("Schau dir @\(username) bei Pace an", "Check out @\(username) on Pace", "Посмотри профиль @\(username) в Pace")
    }

    // MARK: Profil teilen

    static var shareLink: String { t("Link teilen", "Share link", "Поделиться ссылкой") }
    static var shareInPace: String { t("In Pace teilen", "Share in Pace", "Отправить в Pace") }
    static var shareRecipientsHint: String {
        t(
            "Wähle Freunde oder Gruppen. Im Chat erscheint eine Profilkarte, über die man das Profil öffnen kann.",
            "Choose friends or groups. A profile card that opens the profile appears in the chat.",
            "Выбери друзей или группы. В чате появится карточка, по которой можно открыть профиль."
        )
    }

    static var shareChatsUnavailable: String {
        t(
            "Profile in Chats zu teilen ist möglich, sobald die Chats auf dem Server eingerichtet sind. Den Link kannst du schon jetzt teilen.",
            "Sharing profiles in chats is possible once chats are set up on the server. You can already share the link.",
            "Делиться профилями в чатах можно будет, когда на сервере настроят чаты. Ссылкой можно поделиться уже сейчас."
        )
    }

    static var noShareRecipients: String {
        t(
            "Noch keine Freunde oder Gruppen, an die du teilen kannst.",
            "No friends or groups to share with yet.",
            "Пока нет друзей или групп, с которыми можно поделиться."
        )
    }

    static func sendToChats(_ count: Int) -> String {
        PaceLocalization.plural(
            count,
            de: ("An \(count) Chat senden", "An \(count) Chats senden"),
            en: ("Send to \(count) chat", "Send to \(count) chats"),
            ru: ("Отправить в \(count) чат", "Отправить в \(count) чата", "Отправить в \(count) чатов")
        )
    }

    static var chooseRecipients: String { t("Empfänger auswählen", "Choose recipients", "Выбери получателей") }

    // MARK: Melden

    static var reportReasonPrompt: String { t("Warum meldest du das?", "Why are you reporting this?", "Укажи причину жалобы") }
    static var reportDetailsPlaceholder: String {
        t("Weitere Angaben (optional)", "Additional details (optional)", "Подробности (необязательно)")
    }

    static var sendReport: String { t("Meldung senden", "Send report", "Отправить жалобу") }
    static var reportInfo: String {
        t(
            "Die Meldung wird gespeichert und vom Pace-Team geprüft. Die gemeldete Person erfährt nicht, wer sie gemeldet hat.",
            "The report is stored and reviewed by the Pace team. The reported person won't find out who reported them.",
            "Жалоба сохраняется и проверяется командой Pace. Человек, на которого пожаловались, не узнает, кто это сделал."
        )
    }

    static var reportGroup: String { t("Gruppe melden", "Report group", "Пожаловаться на группу") }
    static var reportUser: String { t("Nutzer melden", "Report user", "Пожаловаться на пользователя") }

    // MARK: Gruppen (Übersicht)

    static var yourGroups: String { t("Deine Gruppen", "Your groups", "Твои группы") }
    static var invitations: String { t("Einladungen", "Invitations", "Приглашения") }
    static var join: String { t("Beitreten", "Join", "Вступить") }
    static var joinWithCode: String { t("Mit Code beitreten", "Join with code", "Вступить по коду") }
    static var noGroupsTitle: String { t("Noch keine Gruppen", "No groups yet", "Пока нет групп") }
    static var noGroupsMessage: String {
        t(
            "Gründe eine Gruppe für deine Klasse, dein Team oder deine Freunde – oder tritt mit einem Einladungscode bei. Eure Gruppen-Streak wächst jeden Tag, an dem mindestens ein Drittel das Gruppenziel erreicht.",
            "Start a group for your class, your team or your friends – or join with an invite code. Your group streak grows every day at least a third reach the group goal.",
            "Создай группу для класса, команды или друзей – или вступи по коду приглашения. Серия группы растёт каждый день, когда хотя бы треть участников достигает цели."
        )
    }

    static func invitedBy(_ name: String, memberCount: Int) -> String {
        t("von \(name)", "from \(name)", "от \(name)") + " · " + members(memberCount)
    }

    static var inviteCodePlaceholder: String {
        t("Einladungscode, z. B. K7M2Q9XA", "Invite code, e.g. K7M2Q9XA", "Код приглашения, например K7M2Q9XA")
    }

    static var joinFooter: String {
        t(
            "Den Code bekommst du von einem Mitglied der Gruppe. Mitglieder sehen deinen Anzeigenamen, Benutzernamen und deine Wettbewerbsschritte.",
            "You get the code from a member of the group. Members see your display name, username and competition steps.",
            "Код можно получить у участника группы. Участники видят твоё отображаемое имя, имя пользователя и шаги для рейтинга."
        )
    }

    static func groupRowDetail(reached: Int, required: Int, memberCount: Int) -> String {
        // Mehr erreicht als nötig: nicht „9 von 8 nötig“, sondern gesichert mit der Zahl der Erreichten.
        if required > 0, reached >= required {
            return t(
                "Heute gesichert (\(reached.paceFormatted) erreicht)",
                "Secured today (\(reached.paceFormatted) reached)",
                "Сегодня сохранён (выполнили: \(reached.paceFormatted))"
            ) + " · " + members(memberCount)
        }
        let needed = PaceLocalization.plural(
            required,
            de: ("nötig", "nötig"),
            en: ("needed", "needed"),
            ru: ("нужного", "нужных", "нужных")
        )
        return t(
            "Heute \(reached.paceFormatted) von \(required.paceFormatted) \(needed)",
            "Today \(reached.paceFormatted) of \(required.paceFormatted) \(needed)",
            "Сегодня \(reached.paceFormatted) из \(required.paceFormatted) \(needed)"
        ) + " · " + members(memberCount)
    }

    static func groupRowAccessibility(name: String, streak: Int, reached: Int, required: Int) -> String {
        let neededMembers = PaceLocalization.plural(
            required,
            de: ("nötigen Mitglied", "nötigen Mitgliedern"),
            en: ("required member", "required members"),
            ru: ("нужного участника", "нужных участников", "нужных участников")
        )
        let days = PaceLocalization.days(streak)
        return t(
            "\(name), Serie \(days), heute \(reached.paceFormatted) von \(required.paceFormatted) \(neededMembers)",
            "\(name), streak \(days), today \(reached.paceFormatted) of \(required.paceFormatted) \(neededMembers)",
            "\(name), серия \(days), сегодня \(reached.paceFormatted) из \(required.paceFormatted) \(neededMembers)"
        )
    }

    // MARK: Gruppe erstellen

    static var chooseGroupImage: String { t("Gruppenbild auswählen", "Choose group photo", "Выбрать фото группы") }
    static var changeGroupImage: String { t("Gruppenbild ändern", "Change group photo", "Изменить фото группы") }
    static var groupName: String { t("Gruppenname", "Group name", "Название группы") }
    static var groupNamePlaceholder: String { t("z. B. Abendrunde", "e.g. Evening walk", "например, Вечерняя прогулка") }
    static var groupDescription: String { t("Beschreibung", "Description", "Описание") }
    static var descriptionPlaceholder: String {
        t("Worum geht es in eurer Gruppe?", "What is your group about?", "О чём ваша группа?")
    }

    static var groupType: String { t("Gruppentyp", "Group type", "Тип группы") }
    static var privacy: String { t("Privatsphäre", "Privacy", "Конфиденциальность") }
    static var inviteMembers: String { t("Mitglieder einladen", "Invite members", "Пригласить участников") }
    static var dailyGoalPerMember: String { t("Tagesziel pro Mitglied", "Daily goal per member", "Дневная цель на участника") }
    static var groupStreakRule: String {
        t(
            "Erreichen mindestens ein Drittel der Mitglieder das Ziel, bleibt eure Gruppen-Streak aktiv.",
            "If at least a third of the members reach the goal, your group streak stays active.",
            "Если хотя бы треть участников достигнет цели, серия группы сохранится."
        )
    }

    static var noOneSelected: String { t("Noch niemand ausgewählt", "No one selected yet", "Пока никто не выбран") }
    static var noFriendsToInvite: String {
        t(
            "Du hast noch keine Freunde, die du einladen kannst. Einladungen gibt es nur unter Freunden.",
            "You don't have any friends to invite yet. Invitations are only possible between friends.",
            "У тебя пока нет друзей, которых можно пригласить. Приглашать можно только друзей."
        )
    }

    static func inviteLimitReached(_ maximum: Int) -> String {
        t(
            "Beim Erstellen kannst du höchstens \(maximum) Freunde einladen. Weitere lädst du später in der Gruppe ein.",
            "You can invite up to \(maximum) friends when creating a group. Invite more later from the group.",
            "При создании можно пригласить не больше \(maximum) друзей. Остальных пригласишь позже в группе."
        )
    }

    static func invitedCount(_ count: Int) -> String {
        PaceLocalization.plural(
            count,
            de: ("\(count) Freund ausgewählt", "\(count) Freunde ausgewählt"),
            en: ("\(count) friend selected", "\(count) friends selected"),
            ru: ("Выбран \(count) друг", "Выбрано \(count) друга", "Выбрано \(count) друзей")
        )
    }

    static var imageStorageUnavailable: String {
        t(
            "Gruppenbilder sind möglich, sobald der Bildspeicher auf dem Server eingerichtet ist.",
            "Group photos are possible once image storage is set up on the server.",
            "Фото групп станут доступны, когда на сервере настроят хранилище изображений."
        )
    }

    static var imageTooLarge: String {
        t("Das Bild ist zu groß (höchstens 5 MB).", "The image is too large (max. 5 MB).", "Изображение слишком большое (не более 5 МБ).")
    }

    static var imageNotLoaded: String {
        t("Das Bild konnte nicht geladen werden.", "The image couldn't be loaded.", "Не удалось загрузить изображение.")
    }

    static var removeImage: String { t("Bild entfernen", "Remove photo", "Удалить фото") }
    static var groupImage: String { t("Gruppenbild", "Group photo", "Фото группы") }
    static var groupImageSaved: String { t("Gruppenbild gespeichert.", "Group photo saved.", "Фото группы сохранено.") }
    static var groupImageRemoved: String { t("Gruppenbild entfernt.", "Group photo removed.", "Фото группы удалено.") }

    static var goalPresets: String { t("Häufige Ziele", "Common goals", "Популярные цели") }
    static var decreaseGoal: String { t("Ziel verringern", "Decrease goal", "Уменьшить цель") }
    static var increaseGoal: String { t("Ziel erhöhen", "Increase goal", "Увеличить цель") }
    static var goalChangeHint: String {
        t(
            "Das neue Ziel gilt ab morgen. Heute und vergangene Tage behalten ihr Ziel – die Gruppen-Streak lässt sich dadurch nicht nachträglich retten oder verlieren. Persönliche Tagesziele der Mitglieder bleiben unverändert.",
            "The new goal applies from tomorrow. Today and past days keep their goal – the group streak can't be saved or lost retroactively. Members' personal daily goals stay unchanged.",
            "Новая цель действует с завтрашнего дня. Сегодня и прошлые дни сохраняют свою цель – серию группы нельзя задним числом спасти или потерять. Личные дневные цели участников не меняются."
        )
    }

    static var goalIndependentHint: String {
        t(
            "Das Gruppenziel ist unabhängig von den persönlichen Tageszielen der Mitglieder.",
            "The group goal is independent of the members' personal daily goals.",
            "Цель группы не зависит от личных дневных целей участников."
        )
    }

    // MARK: Gruppendetails

    static func streakTitle(_ days: Int) -> String {
        t(
            "\(PaceLocalization.days(days)) Streak",
            "\(days.paceFormatted)-day streak",
            "Серия: \(PaceLocalization.days(days))"
        )
    }

    static func goalPerMember(_ goal: Int) -> String {
        t(
            "Tagesziel: \(PaceLocalization.steps(goal)) pro Mitglied",
            "Daily goal: \(PaceLocalization.steps(goal)) per member",
            "Дневная цель: \(PaceLocalization.steps(goal)) на участника"
        )
    }

    static func nextGoal(_ goal: Int) -> String {
        t("Ab morgen: \(PaceLocalization.steps(goal))", "From tomorrow: \(PaceLocalization.steps(goal))", "С завтрашнего дня: \(PaceLocalization.steps(goal))")
    }

    static func reachedToday(_ reached: Int, of members: Int) -> String {
        PaceLocalization.plural(
            reached,
            de: (
                "\(reached.paceFormatted) von \(members.paceFormatted) Mitgliedern hat heute das Ziel erreicht",
                "\(reached.paceFormatted) von \(members.paceFormatted) Mitgliedern haben heute das Ziel erreicht"
            ),
            en: (
                "\(reached.paceFormatted) of \(members.paceFormatted) members reached the goal today",
                "\(reached.paceFormatted) of \(members.paceFormatted) members reached the goal today"
            ),
            ru: (
                "Цели сегодня достигли: \(reached.paceFormatted) из \(members.paceFormatted)",
                "Цели сегодня достигли: \(reached.paceFormatted) из \(members.paceFormatted)",
                "Цели сегодня достигли: \(reached.paceFormatted) из \(members.paceFormatted)"
            )
        )
    }

    static func requiredGoals(_ done: Int, of required: Int) -> String {
        PaceLocalization.plural(
            required,
            de: (
                "\(done.paceFormatted) von \(required.paceFormatted) benötigten Ziel",
                "\(done.paceFormatted) von \(required.paceFormatted) benötigten Zielen"
            ),
            en: (
                "\(done.paceFormatted) of \(required.paceFormatted) required goal",
                "\(done.paceFormatted) of \(required.paceFormatted) required goals"
            ),
            ru: (
                "\(done.paceFormatted) из \(required.paceFormatted) необходимой цели",
                "\(done.paceFormatted) из \(required.paceFormatted) необходимых целей",
                "\(done.paceFormatted) из \(required.paceFormatted) необходимых целей"
            )
        )
    }

    static var flameSecured: String { t("Flamme gesichert", "Flame secured", "Огонь сохранён") }

    static func goalsMissing(_ count: Int) -> String {
        PaceLocalization.plural(
            count,
            de: ("Noch \(count.paceFormatted) Ziel", "Noch \(count.paceFormatted) Ziele"),
            en: ("\(count.paceFormatted) goal to go", "\(count.paceFormatted) goals to go"),
            ru: ("Ещё \(count.paceFormatted) цель", "Ещё \(count.paceFormatted) цели", "Ещё \(count.paceFormatted) целей")
        )
    }

    static func thirdRule(required: Int, members: Int) -> String {
        t(
            "Mindestens ⅓ der Mitglieder, aufgerundet: heute \(required.paceFormatted) von \(members.paceFormatted).",
            "At least ⅓ of the members, rounded up: today \(required.paceFormatted) of \(members.paceFormatted).",
            "Не менее ⅓ участников с округлением вверх: сегодня \(required.paceFormatted) из \(members.paceFormatted)."
        )
    }

    static var noMembersToday: String {
        t("Die Gruppe hat gerade keine Mitglieder.", "The group has no members right now.", "Сейчас в группе нет участников.")
    }

    static var groupChat: String { t("Gruppenchat", "Group chat", "Чат группы") }
    static var membersTitle: String { t("Mitglieder", "Members", "Участники") }
    static var todayInGroup: String { t("Heute in der Gruppe", "Today in the group", "Сегодня в группе") }
    static var rankingNotLoaded: String {
        t("Das Ranking konnte nicht geladen werden.", "The ranking couldn't be loaded.", "Не удалось загрузить рейтинг.")
    }

    static var groupGoneTitle: String { t("Nicht mehr in dieser Gruppe", "No longer in this group", "Ты больше не в этой группе") }
    static var groupGoneMessage: String {
        t(
            "Die Gruppe wurde gelöscht oder du bist kein Mitglied mehr.",
            "The group was deleted or you're no longer a member.",
            "Группа удалена, или ты больше не участник."
        )
    }

    static var group: String { t("Gruppe", "Group", "Группа") }
    static var goalReached: String { t("Ziel erreicht", "Goal reached", "Цель достигнута") }

    // MARK: Mitglieder

    static var admin: String { t("Verwaltung", "Admin", "Админ") }
    static var removeFromGroup: String { t("Aus Gruppe entfernen", "Remove from group", "Исключить из группы") }
    static var inviteFriends: String { t("Freunde einladen", "Invite friends", "Пригласить друзей") }
    static var invite: String { t("Einladen", "Invite", "Пригласить") }
    static var pendingInvitations: String { t("Offene Einladungen", "Pending invitations", "Ожидающие приглашения") }
    static var invited: String { t("Eingeladen", "Invited", "Приглашён") }
    static var allFriendsInGroup: String {
        t(
            "Alle deine Freunde sind schon in der Gruppe oder eingeladen.",
            "All your friends are already in the group or invited.",
            "Все твои друзья уже в группе или приглашены."
        )
    }

    static func removeMemberTitle(_ name: String) -> String {
        t("\(name) entfernen?", "Remove \(name)?", "Исключить \(name)?")
    }

    static var removeMemberMessage: String {
        t(
            "Die Person ist danach kein Mitglied mehr und sieht die Gruppe nicht mehr.",
            "The person will no longer be a member and won't see the group anymore.",
            "Этот человек больше не будет участником и перестанет видеть группу."
        )
    }

    static func invitedNotice(_ name: String) -> String {
        t("\(name) wurde eingeladen.", "\(name) has been invited.", "Приглашение для \(name) отправлено.")
    }

    static func alreadyMember(_ name: String) -> String {
        t("\(name) ist bereits Mitglied.", "\(name) is already a member.", "\(name) уже в группе.")
    }

    static func alreadyInvited(_ name: String) -> String {
        t("\(name) ist bereits eingeladen.", "\(name) has already been invited.", "Приглашение для \(name) уже отправлено.")
    }

    static var invitationWithdrawn: String { t("Einladung zurückgezogen.", "Invitation withdrawn.", "Приглашение отозвано.") }

    static func memberRemoved(_ name: String) -> String {
        t("\(name) wurde aus der Gruppe entfernt.", "\(name) has been removed from the group.", "Участник \(name) исключён из группы.")
    }

    // MARK: Gruppeneinstellungen

    static var onlyAdminCanChange: String {
        t(
            "Nur die Person, die die Gruppe verwaltet, kann das ändern.",
            "Only the group's admin can change this.",
            "Изменить это может только администратор группы."
        )
    }

    static var inviteCode: String { t("Einladungscode", "Invite code", "Код приглашения") }
    static var shareCode: String { t("Code teilen", "Share code", "Поделиться кодом") }
    static var newCode: String { t("Neuen Code erstellen", "Create new code", "Создать новый код") }
    static var inviteOnlyCodeHint: String {
        t(
            "Der Einladungscode ist abgeschaltet – nur eingeladene Freunde können beitreten.",
            "The invite code is turned off – only invited friends can join.",
            "Код приглашения отключён – вступить могут только приглашённые друзья."
        )
    }

    static var leaveGroup: String { t("Gruppe verlassen", "Leave group", "Покинуть группу") }
    static var deleteGroup: String { t("Gruppe löschen", "Delete group", "Удалить группу") }
    static var leaveGroupTitle: String { t("Gruppe verlassen?", "Leave group?", "Покинуть группу?") }
    static var deleteGroupTitle: String { t("Gruppe löschen?", "Delete group?", "Удалить группу?") }
    static var regenerateTitle: String {
        t("Neuen Einladungscode erstellen?", "Create a new invite code?", "Создать новый код приглашения?")
    }

    static var leaveOwnerMessage: String {
        t(
            "Die Verwaltung geht an das am längsten beigetretene Mitglied. Bist du das letzte Mitglied, wird die Gruppe gelöscht.",
            "The longest-standing member becomes admin. If you're the last member, the group is deleted.",
            "Администратором станет участник, который дольше всех в группе. Если ты последний участник, группа будет удалена."
        )
    }

    static var leaveMemberMessage: String {
        t(
            "Du kannst nur mit einer neuen Einladung oder einem gültigen Einladungscode wieder beitreten.",
            "You can only rejoin with a new invitation or a valid invite code.",
            "Вернуться можно только по новому приглашению или действующему коду."
        )
    }

    static var deleteMessage: String {
        t(
            "Die Gruppe und ihre Serie werden für alle Mitglieder gelöscht.",
            "The group and its streak are deleted for all members.",
            "Группа и её серия будут удалены для всех участников."
        )
    }

    static var regenerateMessage: String {
        t("Der bisherige Code funktioniert danach nicht mehr.", "The current code will stop working.", "Текущий код перестанет действовать.")
    }

    static var newCodeCreated: String {
        t(
            "Neuer Einladungscode erstellt. Der alte Code gilt nicht mehr.",
            "New invite code created. The old code no longer works.",
            "Создан новый код приглашения. Старый код больше не действует."
        )
    }

    static var groupSaved: String { t("Gruppe gespeichert.", "Group saved.", "Группа сохранена.") }
    static var goalFromTomorrow: String {
        t("Das neue Gruppenziel gilt ab morgen.", "The new group goal applies from tomorrow.", "Новая цель группы действует с завтрашнего дня.")
    }

    static func leftGroup(_ name: String) -> String {
        t("Du hast „\(name)“ verlassen.", "You left “\(name)”.", "Ты больше не в группе «\(name)».")
    }

    static func groupDeleted(_ name: String) -> String {
        t("Gruppe „\(name)“ gelöscht.", "Group “\(name)” deleted.", "Группа «\(name)» удалена.")
    }

    static func joinGroupShareText(name: String, code: String) -> String {
        t(
            "Tritt meiner Pace-Gruppe „\(name)“ bei – Code: \(code)",
            "Join my Pace group “\(name)” – code: \(code)",
            "Вступай в мою группу «\(name)» в Pace – код: \(code)"
        )
    }

    // MARK: Freundesliste

    static var friendsEmptyTitle: String { t("Noch keine Freunde", "No friends yet", "Пока нет друзей") }
    static var friendsEmptyMessage: String {
        t(
            "Suche nach einem Benutzernamen – sobald ihr befreundet seid, vergleicht ihr hier jeden Tag eure Schritte.",
            "Search for a username – once you're friends, you compare your steps here every day.",
            "Найди человека по имени пользователя – когда вы станете друзьями, здесь можно будет каждый день сравнивать шаги."
        )
    }

    static var friendsPrivacyNote: String {
        t(
            "Freunde und Mitglieder deiner Gruppen sehen deinen Anzeigenamen, Benutzernamen und deine Wettbewerbsschritte – keine anderen Gesundheitsdaten und nicht deine Gemeinde.",
            "Friends and members of your groups see your display name, username and competition steps – no other health data and not your municipality.",
            "Друзья и участники твоих групп видят твоё отображаемое имя, имя пользователя и шаги для рейтинга – никаких других данных о здоровье и не твой населённый пункт."
        )
    }

    // MARK: Social-Einstellungen

    static var blockedUsers: String { t("Blockierte Nutzer", "Blocked users", "Заблокированные") }
    static var noBlockedUsers: String { t("Du hast niemanden blockiert.", "You haven't blocked anyone.", "Список заблокированных пуст.") }
    static var blockedUsersHint: String {
        t(
            "Blockierte Personen finden dich nicht in der Suche, können dir keine Anfragen, Einladungen oder Nachrichten schicken.",
            "Blocked people can't find you in search and can't send you requests, invitations or messages.",
            "Заблокированные не найдут тебя в поиске и не смогут отправлять тебе заявки, приглашения или сообщения."
        )
    }

    static var searchVisibility: String { t("Sichtbarkeit in der Suche", "Visibility in search", "Видимость в поиске") }
    static var searchVisibilityText: String {
        t(
            "Ob andere dich über die Suche finden, stellst du im Profil unter „Privatsphäre“ ein.",
            "Whether others can find you in search is set in your profile under “Privacy”.",
            "Можно ли найти тебя через поиск, настраивается в профиле в разделе «Конфиденциальность»."
        )
    }

    static var openProfileSettings: String { t("Im Profil einstellen", "Open profile settings", "Открыть настройки профиля") }
    static var notifications: String { t("Mitteilungen", "Notifications", "Уведомления") }
    static var pushNotReady: String {
        t(
            "Push-Mitteilungen zu Anfragen, Einladungen und Nachrichten folgen, sobald der Versand über den Server eingerichtet ist.",
            "Push notifications for requests, invitations and messages will follow once server delivery is set up.",
            "Push-уведомления о заявках, приглашениях и сообщениях появятся, когда на сервере будет настроена их отправка."
        )
    }

    static var groupInvitations: String { t("Gruppeneinladungen", "Group invitations", "Приглашения в группы") }

    // MARK: Ergänzungen der Unterseiten

    static var openProfileHint: String { t("Öffnet das Profil", "Opens the profile", "Открывает профиль") }
    static func ownUsername(_ username: String) -> String {
        t("Dein Benutzername: \(username)", "Your username: \(username)", "Твоё имя пользователя: \(username)")
    }

    static var profileLoading: String { t("Profil wird geladen …", "Loading profile …", "Загружаем профиль …") }
    static var sendRequest: String { t("Freundschaftsanfrage senden", "Send friend request", "Отправить заявку в друзья") }
    static func charactersLeft(_ count: Int) -> String {
        PaceLocalization.plural(
            count,
            de: ("Noch \(count.paceFormatted) Zeichen", "Noch \(count.paceFormatted) Zeichen"),
            en: ("\(count.paceFormatted) character left", "\(count.paceFormatted) characters left"),
            ru: ("Остался \(count.paceFormatted) символ", "Осталось \(count.paceFormatted) символа", "Осталось \(count.paceFormatted) символов")
        )
    }

    static var groupsNeverPublic: String {
        t(
            "Gruppen sind nie öffentlich auffindbar. Beitreten kann nur, wer eingeladen wurde oder den Code kennt.",
            "Groups are never publicly searchable. Only people who were invited or know the code can join.",
            "Группы никогда не видны в поиске. Вступить может только тот, кого пригласили или кто знает код."
        )
    }

    /// Einheit unter einer großen Schrittzahl, z. B. „Schritte“.
    static func stepsUnit(_ count: Int) -> String {
        PaceLocalization.plural(
            count,
            de: ("Schritt", "Schritte"),
            en: ("step", "steps"),
            ru: ("шаг", "шага", "шагов")
        )
    }

    /// Eigener Name in Listen, z. B. „Niklas (du)“.
    static func youName(_ name: String) -> String {
        t("\(name) (du)", "\(name) (you)", "\(name) (ты)")
    }

    static var removeImageMessage: String {
        t(
            "Die Gruppe zeigt danach wieder das Symbol ihrer Gruppenart.",
            "The group will show the symbol of its type again.",
            "Группа снова будет показывать значок своего типа."
        )
    }

    // MARK: Gruppenkalender

    static var groupCalendar: String { PaceLocalization.text(de: "Gruppenkalender", en: "Group calendar", ru: "Календарь группы") }
    static var groupCalendarSubtitle: String {
        PaceLocalization.text(
            de: "Tagesbeste, Ranglisten und Flamme je Tag",
            en: "Best of the day, rankings and flame for each day",
            ru: "Лучшие дня, рейтинги и огонь по дням"
        )
    }

    // MARK: Spitznamen

    static var nickname: String { PaceLocalization.text(de: "Spitzname", en: "Nickname", ru: "Прозвище") }
    static var addNickname: String {
        PaceLocalization.text(de: "Spitzname vergeben", en: "Add nickname", ru: "Задать прозвище")
    }
    static var editNickname: String {
        PaceLocalization.text(de: "Spitzname ändern", en: "Change nickname", ru: "Изменить прозвище")
    }
    static var removeNickname: String {
        PaceLocalization.text(de: "Spitzname entfernen", en: "Remove nickname", ru: "Удалить прозвище")
    }
    static var nicknamePlaceholder: String {
        PaceLocalization.text(de: "z. B. Laufpartner", en: "e.g. Running buddy", ru: "напр. Напарник")
    }
    static var nicknamePrivacyNote: String {
        PaceLocalization.text(
            de: "Nur du siehst den Spitznamen – überall in Pace statt des Anzeigenamens. Leer lassen entfernt ihn.",
            en: "Only you can see the nickname – everywhere in Pace instead of the display name. Leave it empty to remove it.",
            ru: "Прозвище видишь только ты – везде в Pace вместо отображаемого имени. Оставь поле пустым, чтобы удалить его."
        )
    }
    /// Zweite Zeile im Profil, wenn ein Spitzname gesetzt ist: der echte Anzeigename.
    static func displayNameLine(_ name: String) -> String {
        PaceLocalization.text(de: "Anzeigename: \(name)", en: "Display name: \(name)", ru: "Отображаемое имя: \(name)")
    }
    static func nicknameProblem(_ violation: DisplayNameRules.Violation) -> String {
        switch violation {
        case .tooLong:
            PaceLocalization.text(
                de: "Höchstens \(NicknameRules.maxLength) Zeichen.",
                en: "At most \(NicknameRules.maxLength) characters.",
                ru: "Не более \(NicknameRules.maxLength) символов."
            )
        case .invalidCharacters, .empty:
            PaceLocalization.text(
                de: "Bitte ohne Steuer- oder unsichtbare Zeichen.",
                en: "Please don't use control or invisible characters.",
                ru: "Без управляющих и невидимых символов."
            )
        }
    }

    // MARK: Fehler

    /// Text für einen Fehler beim Laden.
    static func message(for error: any Error) -> String {
        (error as? SocialError)?.message ?? SocialError.unexpected("").message
    }

    /// Text für einen Fehler einer Aktion: „nicht eingerichtet“ betrifft hier nur diese eine Funktion.
    static func actionMessage(for error: any Error) -> String {
        if let error = error as? SocialError, error == .unavailable {
            return featureUnavailable
        }
        return message(for: error)
    }
}
