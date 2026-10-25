import Foundation
import PaceCore

/// Ein erklärender Abschnitt (Hilfe, Datenschutz, Rechtliches): Symbol, Titel und Text.
public struct InfoSection: Identifiable, Equatable, Sendable {
    public let id: String
    public let systemImage: String
    public let title: String
    public let body: String

    public init(id: String, systemImage: String, title: String, body: String) {
        self.id = id
        self.systemImage = systemImage
        self.title = title
        self.body = body
    }
}

/// Häufige Fragen – nur zu Funktionen, die es in Pace wirklich gibt. Die Texte werden bei jedem Abruf in der aktuellen
/// Sprache erzeugt.
public enum HelpContent {
    public static var faq: [InfoSection] {
        [
            InfoSection(
                id: "steps",
                systemImage: "figure.walk",
                title: PaceLocalization.text(
                    de: "Woher kommen meine Schritte?",
                    en: "Where do my steps come from?",
                    ru: "Откуда берутся мои шаги?"
                ),
                body: PaceLocalization.text(
                    de: "Pace liest deine Schritte aus Apple Health. Für Rankings, Freunde und Gruppen zählen nur Schritte, die dein iPhone oder deine Apple Watch selbst gemessen haben – von Hand eingetragene Schritte werden nicht berücksichtigt.",
                    en: "Pace reads your steps from Apple Health. Rankings, friends and groups only count steps measured by your iPhone or Apple Watch – steps entered by hand are not included.",
                    ru: "Pace берёт шаги из приложения «Здоровье». В рейтингах, у друзей и в группах учитываются только шаги, измеренные iPhone или Apple Watch, – введённые вручную шаги не засчитываются."
                )
            ),
            InfoSection(
                id: "ranking",
                systemImage: "chart.bar",
                title: PaceLocalization.text(
                    de: "Warum erscheine ich nicht im regionalen Ranking?",
                    en: "Why don't I appear in the regional ranking?",
                    ru: "Почему меня нет в региональном рейтинге?"
                ),
                body: PaceLocalization.text(
                    de: "Regionale Rankings zeigen nur Personen, die zugestimmt haben. Du kannst das im Profil unter „Sichtbarkeit in Rankings“ jederzeit ein- oder ausschalten. Rankings mit Freunden und in Gruppen sind davon unabhängig.",
                    en: "Regional rankings only show people who have agreed to it. You can turn this on or off at any time in your profile under “Visibility in rankings”. Rankings with friends and in groups are separate from this.",
                    ru: "В региональных рейтингах отображаются только те, кто дал согласие. Включить или выключить это можно в любой момент в профиле в разделе «Видимость в рейтингах». Рейтинги с друзьями и в группах от этого не зависят."
                )
            ),
            InfoSection(
                id: "friends",
                systemImage: "person.2",
                title: PaceLocalization.text(
                    de: "Was sehen meine Freunde und Gruppen?",
                    en: "What can my friends and groups see?",
                    ru: "Что видят мои друзья и группы?"
                ),
                body: PaceLocalization.text(
                    de: "Deinen Anzeigenamen, deinen Benutzernamen, dein Profilbild und deine täglichen Wettbewerbsschritte. Andere Gesundheitsdaten wie Puls, Distanz oder Kalorien verlassen dein iPhone nicht.",
                    en: "Your display name, username, profile picture and your daily competition steps. Other health data such as heart rate, distance or calories never leave your iPhone.",
                    ru: "Твоё отображаемое имя, имя пользователя, фото профиля и ежедневные шаги для соревнований. Другие данные о здоровье, например пульс, расстояние или калории, не покидают твой iPhone."
                )
            ),
            InfoSection(
                id: "streak",
                systemImage: "flame",
                title: PaceLocalization.text(
                    de: "Wie funktioniert meine Serie?",
                    en: "How does my streak work?",
                    ru: "Как работает моя серия?"
                ),
                body: PaceLocalization.text(
                    de: "Deine Serie zählt die Tage in Folge, an denen du dein Tagesziel erreicht hast. Änderst du dein Tagesziel, gilt es ab heute – vergangene Tage behalten ihr damaliges Ziel.",
                    en: "Your streak counts the days in a row on which you reached your daily goal. If you change your daily goal, it applies from today – past days keep the goal they had.",
                    ru: "Серия считает дни подряд, в которые ты достигал дневной цели. Новая дневная цель действует с сегодняшнего дня – для прошлых дней сохраняется прежняя цель."
                )
            ),
            InfoSection(
                id: "addFriends",
                systemImage: "person.badge.plus",
                title: PaceLocalization.text(
                    de: "Wie füge ich Freunde hinzu?",
                    en: "How do I add friends?",
                    ru: "Как добавить друзей?"
                ),
                body: PaceLocalization.text(
                    de: "Im Social-Tab unter „Freund hinzufügen“ über den Benutzernamen – oder du teilst deinen Profil-Link aus „Konto & Profil“. Die andere Person muss deine Anfrage annehmen.",
                    en: "In the Social tab under “Add friend” using their username – or share your profile link from “Account & profile”. The other person has to accept your request.",
                    ru: "Во вкладке «Друзья» через «Добавить друга» по имени пользователя – или поделись ссылкой на профиль из раздела «Аккаунт и профиль». Другой человек должен принять запрос."
                )
            ),
            InfoSection(
                id: "newPhone",
                systemImage: "iphone",
                title: PaceLocalization.text(
                    de: "Was passiert auf einem neuen iPhone?",
                    en: "What happens on a new iPhone?",
                    ru: "Что будет на новом iPhone?"
                ),
                body: PaceLocalization.text(
                    de: "Dein Konto ist derzeit an dieses iPhone gebunden und lässt sich noch nicht übertragen. Eine dauerhafte Anmeldung ist in Vorbereitung.",
                    en: "Your account is currently tied to this iPhone and can't be transferred yet. A permanent sign-in is being prepared.",
                    ru: "Сейчас аккаунт привязан к этому iPhone, и перенести его пока нельзя. Постоянный вход находится в разработке."
                )
            ),
            InfoSection(
                id: "reminder",
                systemImage: "bell",
                title: PaceLocalization.text(
                    de: "Warum bekomme ich keine Erinnerung?",
                    en: "Why am I not getting reminders?",
                    ru: "Почему я не получаю напоминания?"
                ),
                body: PaceLocalization.text(
                    de: "Prüfe unter „Mitteilungen“, ob die Erinnerung eingeschaltet ist und iOS Mitteilungen für Pace erlaubt. Hast du dein Tagesziel schon erreicht und Pace danach geöffnet, erinnert dich Pace an diesem Tag nicht mehr.",
                    en: "Check under “Notifications” that the reminder is turned on and iOS allows notifications for Pace. If you've already reached your daily goal and opened Pace since, Pace won't remind you again that day.",
                    ru: "Проверь в разделе «Уведомления», что напоминание включено и iOS разрешает уведомления для Pace. Если дневная цель уже достигнута и ты после этого открывал Pace, в этот день Pace больше не напомнит."
                )
            ),
        ]
    }
}

/// Erklärungen auf „Datenschutz & Daten“ und Entwürfe der rechtlichen Texte.
///
/// Alle Texte sind Entwürfe: Sie beschreiben die technische Umsetzung in Pace und müssen vom Betreiber rechtlich geprüft
/// und ergänzt werden (Verantwortlicher, Kontakt, Rechtsgrundlagen). Es werden keine Adressen erfunden.
public enum PrivacyContent {
    public static var dataSections: [InfoSection] {
        [
            InfoSection(
                id: "health",
                systemImage: "heart.text.square",
                title: PaceLocalization.text(de: "Gesundheitsdaten (Apple Health)", en: "Health data (Apple Health)", ru: "Данные о здоровье (Apple Health)"),
                body: PaceLocalization.text(
                    de: "Pace liest Schritte, Distanz, aktive Energie, Stockwerke, Trainingsminuten und – wenn du es erlaubst – Ruhe- und Gehpuls aus Apple Health, um deinen Tag anzuzeigen. Diese Werte bleiben auf deinem iPhone und werden nicht auf den Server übertragen.",
                    en: "Pace reads steps, distance, active energy, flights climbed, exercise minutes and – if you allow it – resting and walking heart rate from Apple Health to show your day. These values stay on your iPhone and are not sent to the server.",
                    ru: "Pace читает из «Здоровья» шаги, расстояние, активную энергию, этажи, минуты тренировок и – если ты разрешишь – пульс в покое и при ходьбе, чтобы показать твой день. Эти данные остаются на iPhone и не передаются на сервер."
                )
            ),
            InfoSection(
                id: "competition",
                systemImage: "figure.walk",
                title: PaceLocalization.text(de: "Wettbewerbsschritte", en: "Competition steps", ru: "Шаги для соревнований"),
                body: PaceLocalization.text(
                    de: "Für Rankings, Freunde und Gruppen überträgt Pace nur deine gemessene Schrittzahl pro Tag – ohne Uhrzeiten, Orte oder andere Gesundheitswerte. Von Hand eingetragene Schritte werden nicht übertragen.",
                    en: "For rankings, friends and groups, Pace only sends your measured step count per day – without times, locations or other health values. Steps entered by hand are not sent.",
                    ru: "Для рейтингов, друзей и групп Pace передаёт только измеренное количество шагов за день – без времени, мест и других показателей здоровья. Введённые вручную шаги не передаются."
                )
            ),
            InfoSection(
                id: "profile",
                systemImage: "person.crop.circle",
                title: PaceLocalization.text(de: "Profil, Freunde und Gruppen", en: "Profile, friends and groups", ru: "Профиль, друзья и группы"),
                body: PaceLocalization.text(
                    de: "Auf dem Server gespeichert werden dein Anzeigename, dein Benutzername, dein Profilbild, deine Gemeinde (kein Standort), deine Zustimmung zu regionalen Rankings, Freundschaften, Anfragen, Gruppen und Blockierungen.",
                    en: "The server stores your display name, username, profile picture, your municipality (no location), your consent to regional rankings, friendships, requests, groups and blocks.",
                    ru: "На сервере хранятся отображаемое имя, имя пользователя, фото профиля, твой муниципалитет (без геолокации), согласие на региональные рейтинги, дружба, запросы, группы и блокировки."
                )
            ),
            InfoSection(
                id: "chats",
                systemImage: "bubble.left.and.bubble.right",
                title: PaceLocalization.text(de: "Chats und Bilder", en: "Chats and images", ru: "Чаты и изображения"),
                body: PaceLocalization.text(
                    de: "Nachrichten und geteilte Bilder sind nur für die Mitglieder der jeweiligen Unterhaltung lesbar. Gemeldete Inhalte werden zur Prüfung gespeichert. Bei der GIF-Suche gehen deine Suchbegriffe an GIPHY; ein gewähltes GIF wird als Kopie im Chat gespeichert, nicht als Link.",
                    en: "Messages and shared images can only be read by the members of the conversation. Reported content is stored for review. When you search for GIFs, your search terms are sent to GIPHY; a chosen GIF is stored in the chat as a copy, not as a link.",
                    ru: "Сообщения и изображения доступны только участникам переписки. Жалобы на контент сохраняются для проверки. При поиске GIF запросы передаются GIPHY; выбранный GIF сохраняется в чате как копия, а не как ссылка."
                )
            ),
            InfoSection(
                id: "retention",
                systemImage: "clock.arrow.circlepath",
                title: PaceLocalization.text(de: "Aufbewahrung und Löschung", en: "Retention and deletion", ru: "Хранение и удаление"),
                body: PaceLocalization.text(
                    de: "Deine Daten bleiben gespeichert, solange dein Konto besteht. Wenn du dein Konto löschst, werden Profil, Tageswerte, Freundschaften, Mitgliedschaften, Nachrichten und eigene Bilder vom Server entfernt und die Daten auf diesem iPhone gelöscht.",
                    en: "Your data is kept as long as your account exists. When you delete your account, your profile, daily values, friendships, memberships, messages and your own images are removed from the server and the data on this iPhone is erased.",
                    ru: "Данные хранятся, пока существует аккаунт. При удалении аккаунта профиль, дневные значения, дружба, участие в группах, сообщения и твои изображения удаляются с сервера, а данные на этом iPhone стираются."
                )
            ),
        ]
    }

    /// Inhalt eines rechtlichen Dokuments (Entwurf bzw. vom Betreiber zu ergänzen).
    public static func sections(for document: LegalDocument) -> [InfoSection] {
        switch document {
        case .privacyPolicy:
            [
                InfoSection(
                    id: "controller",
                    systemImage: "building.2",
                    title: PaceLocalization.text(de: "Verantwortlicher", en: "Controller", ru: "Ответственное лицо"),
                    body: operatorToComplete
                ),
            ] + dataSections + [
                InfoSection(
                    id: "rights",
                    systemImage: "checkmark.shield",
                    title: PaceLocalization.text(de: "Deine Rechte", en: "Your rights", ru: "Твои права"),
                    body: PaceLocalization.text(
                        de: "Du kannst deine Daten jederzeit in Pace exportieren (Auskunft und Datenübertragbarkeit) und dein Konto mit allen Daten löschen. Weitere Rechte wie Berichtigung, Einschränkung und Beschwerde bei einer Aufsichtsbehörde sowie die Rechtsgrundlagen ergänzt der Betreiber.",
                        en: "You can export your data in Pace at any time (access and portability) and delete your account with all data. Further rights such as rectification, restriction and complaints to a supervisory authority, as well as the legal bases, will be added by the operator.",
                        ru: "Ты можешь в любой момент экспортировать свои данные в Pace (доступ и переносимость) и удалить аккаунт со всеми данными. Другие права – исправление, ограничение обработки, жалоба в надзорный орган – и правовые основания дополнит оператор."
                    )
                ),
            ]
        case .imprint:
            [
                InfoSection(
                    id: "imprint",
                    systemImage: "doc.text",
                    title: PaceLocalization.text(de: "Anbieter", en: "Provider", ru: "Поставщик"),
                    body: operatorToComplete
                ),
            ]
        case .terms:
            [
                InfoSection(
                    id: "terms",
                    systemImage: "doc.plaintext",
                    title: PaceLocalization.text(de: "Nutzungsbedingungen", en: "Terms of use", ru: "Условия использования"),
                    body: PaceLocalization.text(
                        de: "Nutzungsbedingungen für Pace liegen noch nicht vor und werden vom Betreiber ergänzt. Bis dahin gilt: Sei respektvoll, teile nur Inhalte, die du teilen darfst, und melde unangemessene Inhalte über die Melden-Funktion.",
                        en: "Terms of use for Pace are not available yet and will be added by the operator. Until then: be respectful, only share content you're allowed to share, and report inappropriate content using the report function.",
                        ru: "Условия использования Pace пока не готовы и будут добавлены оператором. До тех пор: будь вежлив, делись только тем, чем имеешь право делиться, и сообщай о неприемлемом контенте через функцию жалобы."
                    )
                ),
            ]
        }
    }

    static var operatorToComplete: String {
        PaceLocalization.text(
            de: "Name und Anschrift des Betreibers sowie Kontaktmöglichkeiten werden vom Betreiber ergänzt.",
            en: "The operator's name, address and contact details will be added by the operator.",
            ru: "Имя и адрес оператора, а также контактные данные будут добавлены оператором."
        )
    }

    /// Kennzeichnung der Entwürfe auf den Seiten.
    public static var draftExplanation: String {
        PaceLocalization.text(
            de: "Diese Texte beschreiben, wie Pace technisch mit deinen Daten umgeht. Sie sind noch nicht rechtsverbindlich und werden vom Betreiber geprüft und ergänzt.",
            en: "These texts describe how Pace technically handles your data. They are not legally binding yet and will be reviewed and completed by the operator.",
            ru: "Эти тексты описывают, как Pace технически обращается с твоими данными. Они пока не имеют юридической силы и будут проверены и дополнены оператором."
        )
    }
}
