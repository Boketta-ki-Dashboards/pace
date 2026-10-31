import Foundation
import Observation

/// Pace-Bot: ein einfacher, vollständig vorprogrammierter Hilfe-Assistent (Auftrag 6).
///
/// - Kein KI-Modell, keine externen Server, keine laufenden Kosten: Fragen und Antworten liegen fest in der App
///   (Deutsch, Englisch, Russisch) und funktionieren offline.
/// - Freie Eingaben werden nur über Stichwörter einem vorhandenen Thema zugeordnet. Ist das nicht eindeutig, sagt der
///   Bot ehrlich, dass er dazu keine Antwort hat – er erfindet nichts.
/// - Der Verlauf liegt begrenzt nur auf dem Gerät (keine Datenbank, keine Echtzeit, keine Benutzeridentität) und
///   speichert Themen statt Texte: Nach einem Sprachwechsel erscheinen alle Antworten in der neuen Sprache.
public enum PaceHelpTopic: String, CaseIterable, Codable, Sendable, Identifiable {
    case howItWorks = "how_it_works"
    case stepCounting = "step_counting"
    case stepMismatch = "step_mismatch"
    case rankings
    case flame
    case groupFlame = "group_flame"
    case addFriends = "add_friends"
    case createGroup = "create_group"
    case customizeHome = "customize_home"
    case dailyGoal = "daily_goal"
    case editProfile = "edit_profile"
    case privacy
    case languageDesign = "language_design"
    case reportUser = "report_user"
    case reportBug = "report_bug"

    public var id: String { rawValue }

    public var question: String {
        switch self {
        case .howItWorks: PaceLocalization.text(de: "Wie funktioniert Pace?", en: "How does Pace work?", ru: "Как работает Pace?")
        case .stepCounting: PaceLocalization.text(de: "Wie werden meine Schritte gezählt?", en: "How are my steps counted?", ru: "Как считаются мои шаги?")
        case .stepMismatch: PaceLocalization.text(de: "Warum stimmen meine Schritte nicht sofort überein?", en: "Why don't my steps match right away?", ru: "Почему шаги совпадают не сразу?")
        case .rankings: PaceLocalization.text(de: "Wie funktionieren die Rankings?", en: "How do the rankings work?", ru: "Как работают рейтинги?")
        case .flame: PaceLocalization.text(de: "Wie funktioniert meine Flamme?", en: "How does my flame work?", ru: "Как работает мой огонь?")
        case .groupFlame: PaceLocalization.text(de: "Wie funktioniert eine Gruppenflamme?", en: "How does a group flame work?", ru: "Как работает огонь группы?")
        case .addFriends: PaceLocalization.text(de: "Wie füge ich Freunde hinzu?", en: "How do I add friends?", ru: "Как добавить друзей?")
        case .createGroup: PaceLocalization.text(de: "Wie erstelle ich eine Gruppe?", en: "How do I create a group?", ru: "Как создать группу?")
        case .customizeHome: PaceLocalization.text(de: "Wie passe ich Home an?", en: "How do I customize Home?", ru: "Как настроить «Главную»?")
        case .dailyGoal: PaceLocalization.text(de: "Wie ändere ich mein Tagesziel?", en: "How do I change my daily goal?", ru: "Как изменить дневную цель?")
        case .editProfile: PaceLocalization.text(de: "Wie ändere ich mein Profil?", en: "How do I edit my profile?", ru: "Как изменить профиль?")
        case .privacy: PaceLocalization.text(de: "Wie ändere ich Datenschutz-Einstellungen?", en: "How do I change privacy settings?", ru: "Как изменить настройки конфиденциальности?")
        case .languageDesign: PaceLocalization.text(de: "Wie ändere ich die Sprache oder das Design?", en: "How do I change the language or design?", ru: "Как изменить язык или оформление?")
        case .reportUser: PaceLocalization.text(de: "Wie melde ich einen Nutzer?", en: "How do I report a user?", ru: "Как пожаловаться на пользователя?")
        case .reportBug: PaceLocalization.text(de: "Wie melde ich einen technischen Fehler?", en: "How do I report a technical problem?", ru: "Как сообщить о технической ошибке?")
        }
    }

    public var answer: String {
        switch self {
        case .howItWorks:
            PaceLocalization.text(
                de: "Pace zählt deine Schritte automatisch über Apple Health – du musst nichts eintragen. Auf Home siehst du deinen Fortschritt zum persönlichen Tagesziel. In den Rankings vergleichst du dich mit deiner Region oder deinen Freunden. Mit Freunden und in Gruppen bleibt ihr über Chats in Kontakt. Erreichst du dein Tagesziel mehrere Tage hintereinander, wächst deine Flamme; Gruppen haben eine gemeinsame Gruppenflamme.",
                en: "Pace counts your steps automatically through Apple Health – you don't have to enter anything. On Home you see your progress towards your personal daily goal. In the rankings you compare yourself with your region or your friends. With friends and in groups you stay in touch through chats. Reach your daily goal several days in a row and your flame grows; groups have a shared group flame.",
                ru: "Pace автоматически считает шаги через Apple Health – ничего вводить не нужно. На вкладке «Главная» видно, как ты продвигаешься к своей дневной цели. В рейтингах ты сравниваешь себя с регионом или друзьями. С друзьями и в группах вы общаетесь в чатах. Если ты достигаешь цели несколько дней подряд, твой огонь растёт; у групп есть общий огонь группы."
            )
        case .stepCounting:
            PaceLocalization.text(
                de: "Pace liest deine Schritte aus Apple Health. Solange Pace geöffnet ist, zählt der Bewegungssensor deines iPhones zusätzlich live mit – diese Anzeige ist vorläufig. Für die Rankings zählen nur bestätigte Wettbewerbsschritte aus Apple Health; von Hand eingetragene Schritte zählen nicht.",
                en: "Pace reads your steps from Apple Health. While Pace is open, your iPhone's motion sensor also counts live – this display is preliminary. Rankings only use confirmed competition steps from Apple Health; manually entered steps don't count.",
                ru: "Pace берёт шаги из Apple Health. Пока Pace открыт, датчик движения iPhone дополнительно считает шаги в реальном времени – это предварительное значение. В рейтингах учитываются только подтверждённые соревновательные шаги из Apple Health; шаги, введённые вручную, не учитываются."
            )
        case .stepMismatch:
            PaceLocalization.text(
                de: "Apple Health und der Bewegungssensor aktualisieren nicht immer gleichzeitig. Die Live-Anzeige ist deshalb vorläufig: Bestätigt Apple Health weniger Schritte, übernimmt Pace etwa 20 Minuten nach deinem letzten Schritt den Wert aus Apple Health. Rankings können sich etwas verzögern. Prüfe außerdem, ob Pace Zugriff auf deine Schritte (Health-App) und auf „Bewegung & Fitness“ hat.",
                en: "Apple Health and the motion sensor don't always update at the same time. The live display is therefore preliminary: if Apple Health confirms fewer steps, Pace adopts the Apple Health value about 20 minutes after your last step. Rankings can be slightly delayed. Also check that Pace has access to your steps (Health app) and to “Motion & Fitness”.",
                ru: "Apple Health и датчик движения обновляются не всегда одновременно. Поэтому значение в реальном времени предварительное: если Apple Health подтверждает меньше шагов, примерно через 20 минут после последнего шага Pace берёт значение из Apple Health. Рейтинги могут обновляться с небольшой задержкой. Также проверь, есть ли у Pace доступ к шагам (приложение «Здоровье») и к разделу «Движение и фитнес»."
            )
        case .rankings:
            PaceLocalization.text(
                de: "Es gibt regionale Rankings für deine Stadt, deinen Landkreis, dein Bundesland und dein Land sowie ein Ranking mit deinen Freunden. Gezählt werden bestätigte Wettbewerbsschritte aus Apple Health. In den regionalen Rankings erscheinst du nur, wenn du das unter Profil → „Sichtbarkeit in Rankings“ eingeschaltet hast.",
                en: "There are regional rankings for your city, district, state and country, plus a ranking with your friends. Confirmed competition steps from Apple Health count. You only appear in regional rankings if you've switched that on under Profile → “Visibility in rankings”.",
                ru: "Есть региональные рейтинги по городу, району, земле и стране, а также рейтинг среди друзей. Учитываются подтверждённые соревновательные шаги из Apple Health. В региональных рейтингах ты появляешься, только если это включено в «Профиль» → «Видимость в рейтингах»."
            )
        case .flame:
            PaceLocalization.text(
                de: "Jeder Tag, an dem du dein Tagesziel erreichst, zählt für deine Serie. Mehrere erfolgreiche Tage hintereinander lassen deine Flamme wachsen. Im Flammenkalender (über das Serien-Widget auf Home) siehst du, an welchen Tagen du dein Ziel erreicht hast – jeweils mit dem damals gültigen Ziel.",
                en: "Every day you reach your daily goal counts towards your streak. Several successful days in a row make your flame grow. The flame calendar (via the streak widget on Home) shows on which days you reached your goal – each with the goal that applied then.",
                ru: "Каждый день, когда ты достигаешь дневной цели, засчитывается в серию. Несколько успешных дней подряд делают твой огонь больше. В календаре огня (через виджет серии на вкладке «Главная») видно, в какие дни цель была достигнута – с той целью, что действовала тогда."
            )
        case .groupFlame:
            PaceLocalization.text(
                de: "Eine Gruppenflamme bleibt an einem Tag erhalten, wenn mindestens ein Drittel der Mitglieder (aufgerundet) das Tagesziel der Gruppe erreicht – bei 12 Mitgliedern also 4. Es müssen nicht alle ihr Ziel schaffen. In der Gruppe siehst du, wie viele es heute schon geschafft haben.",
                en: "A group flame continues on a day when at least one third of the members (rounded up) reach the group's daily goal – with 12 members that's 4. Not everyone has to make it. In the group you can see how many have already made it today.",
                ru: "Огонь группы сохраняется в этот день, если хотя бы треть участников (с округлением вверх) достигла дневной цели группы – при 12 участниках это 4. Выполнять цель всем не обязательно. В группе видно, сколько участников уже справились сегодня."
            )
        case .addFriends:
            PaceLocalization.text(
                de: "Öffne Social und tippe auf „Freund hinzufügen“. Suche nach dem Benutzernamen und sende eine Anfrage. Sobald die andere Person sie unter „Freundschaftsanfragen“ (Briefumschlag oben rechts) annimmt, seid ihr befreundet und könnt euch vergleichen und schreiben.",
                en: "Open Social and tap “Add friend”. Search for the username and send a request. Once the other person accepts it under “Friend requests” (envelope at the top right), you're friends and can compare and message each other.",
                ru: "Открой вкладку «Друзья» и нажми «Добавить друга». Найди имя пользователя и отправь заявку. Когда другой человек примет её в разделе «Заявки в друзья» (значок конверта вверху справа), вы станете друзьями и сможете сравнивать шаги и переписываться."
            )
        case .createGroup:
            PaceLocalization.text(
                de: "Öffne Social und tippe auf „Gruppe erstellen“. Gib einen Gruppennamen ein, wähle das Tagesziel der Gruppe und lade Freunde ein – oder teile später den Einladungscode.",
                en: "Open Social and tap “Create group”. Enter a group name, choose the group's daily goal and invite friends – or share the invite code later.",
                ru: "Открой вкладку «Друзья» и нажми «Создать группу». Введи название, выбери дневную цель группы и пригласи друзей – или позже поделись кодом приглашения."
            )
        case .customizeHome:
            PaceLocalization.text(
                de: "Tippe auf Home auf „Anpassen“. Mit „+ Widget hinzufügen“ kommen neue Widgets dazu, über „Größe auswählen“ änderst du die Größe, am Griff mit den sechs Punkten verschiebst du ein Widget, mit dem X entfernst du es. Zum Schluss auf „Fertig“ tippen.",
                en: "Tap “Customize” on Home. “+ Add widget” adds new widgets, “Choose size” changes the size, the handle with six dots moves a widget and the X removes it. Tap “Done” when you're finished.",
                ru: "На вкладке «Главная» нажми «Настроить». «+ Добавить виджет» добавляет виджеты, «Выбрать размер» меняет размер, виджет можно перетащить за ручку с шестью точками, крестик удаляет его. В конце нажми «Готово»."
            )
        case .dailyGoal:
            PaceLocalization.text(
                de: "Tippe im Schritte-Widget auf Home auf „Tagesziel ändern“ oder öffne Profil → Deine Aktivität → Tagesziel. Das neue Ziel gilt ab heute; frühere Tage behalten ihr damaliges Ziel.",
                en: "Tap “Change daily goal” in the steps widget on Home or open Profile → Your activity → Daily goal. The new goal applies from today; earlier days keep the goal they had.",
                ru: "Нажми «Изменить цель» в виджете шагов на вкладке «Главная» или открой «Профиль» → «Твоя активность» → «Дневная цель». Новая цель действует с сегодняшнего дня; прошлые дни сохраняют свою цель."
            )
        case .editProfile:
            PaceLocalization.text(
                de: "Öffne Profil und tippe neben deinem Profilbild auf „Bearbeiten“. Dort kannst du ein Banner, eine kurze Bio, bis zu fünf Interessen und – freiwillig – sichtbare Auszeichnungen festlegen. Profilbild und Namen änderst du unter Profil → Konto & Profil.",
                en: "Open Profile and tap “Edit” next to your photo. There you can set a banner, a short bio, up to five interests and – optionally – visible achievements. Change your photo and names under Profile → Account & profile.",
                ru: "Открой профиль и нажми «Изменить» рядом с фото. Там можно задать обложку, короткое описание, до пяти интересов и – по желанию – видимые награды. Фото и имена меняются в разделе «Профиль» → «Аккаунт и профиль»."
            )
        case .privacy:
            PaceLocalization.text(
                de: "Unter Profil → Privatsphäre & Sicherheit legst du fest, ob andere dich in der Suche finden, und verwaltest blockierte Personen. Ob du in regionalen Rankings erscheinst, stellst du unter Profil → „Sichtbarkeit in Rankings“ ein. Deine Wettbewerbsschritte sehen deine Freunde, die Mitglieder deiner Gruppen und – nur wenn eingeschaltet – andere in den Rankings deiner Regionen.",
                en: "Under Profile → Privacy & security you decide whether others can find you in search and manage blocked people. Whether you appear in regional rankings is set under Profile → “Visibility in rankings”. Your competition steps are visible to your friends, the members of your groups and – only if switched on – others in your regional rankings.",
                ru: "В разделе «Профиль» → «Конфиденциальность и безопасность» можно решить, находят ли тебя другие в поиске, и управлять заблокированными пользователями. Показывать ли тебя в региональных рейтингах, настраивается в «Профиль» → «Видимость в рейтингах». Твои шаги для соревнований видят друзья, участники твоих групп и – только если это включено – другие пользователи в рейтингах твоих регионов."
            )
        case .languageDesign:
            PaceLocalization.text(
                de: "Öffne Profil → Darstellung & Sprache. Dort wählst du Automatisch, Hell oder Dunkel, das App-Icon und die Sprache (Deutsch, Englisch, Russisch oder wie dein iPhone).",
                en: "Open Profile → Appearance & language. There you choose Automatic, Light or Dark, the app icon and the language (German, English, Russian or like your iPhone).",
                ru: "Открой «Профиль» → «Оформление и язык». Там можно выбрать «Автоматически», «Светлая» или «Тёмная», значок приложения и язык (немецкий, английский, русский или как на iPhone)."
            )
        case .reportUser:
            PaceLocalization.text(
                de: "Öffne das Profil der Person und wähle „Nutzer melden“. Dort kannst du sie auch blockieren. Eine Gruppe meldest du in den Gruppeneinstellungen („Gruppe melden“), eine einzelne Nachricht durch langes Drücken im Chat („Nachricht melden“).",
                en: "Open the person's profile and choose “Report user”. You can also block them there. Report a group in the group settings (“Report group”) and a single message by long-pressing it in the chat (“Report message”).",
                ru: "Открой профиль человека и выбери «Пожаловаться на пользователя». Там же можно заблокировать. На группу жалуются в настройках группы («Пожаловаться на группу»), на отдельное сообщение – долгим нажатием в чате («Пожаловаться на сообщение»)."
            )
        case .reportBug:
            PaceLocalization.text(
                de: "Am besten über Profil → Daten, Hilfe & Rechtliches → Hilfe & Feedback → „Problem melden“. Beschreibe kurz, was passiert ist. Gespeichert wird deine Nachricht mit deinem Konto und der App-Version – keine Gesundheitsdaten und keine Chats.",
                en: "Best via Profile → Data, help & legal → Help & feedback → “Report a problem”. Briefly describe what happened. Your message is stored with your account and the app version – no health data and no chats.",
                ru: "Лучше всего через «Профиль» → «Данные, помощь и правовая информация» → «Помощь и отзывы» → «Сообщить о проблеме». Коротко опиши, что произошло. Сообщение сохраняется вместе с твоим аккаунтом и версией приложения – без данных о здоровье и чатов."
            )
        }
    }

    /// Stichwörter für die freie Eingabe (klein, „ё“ als „е“): Ein Stichwort trifft, wenn ein Wort der Eingabe damit
    /// **beginnt** („count“ trifft „counted“, aber nicht „account“); mehrere Wörter müssen aufeinander folgen; ein
    /// abschließendes `$` verlangt das ganze Wort („hell$“ trifft nicht „hello“).
    var keywords: [String] {
        switch self {
        case .howItWorks: ["wie funktioniert pace", "how does pace", "как работает pace", "was ist pace", "what is pace", "что такое pace"]
        case .stepCounting: ["schritt", "zähl", "gezählt", "step", "count", "шаг", "счит", "подсч"]
        case .stepMismatch: ["stimm", "überein", "falsch", "unterschied", "verzöger", "abweich", "mismatch", "match", "wrong", "differ", "delay", "совпад", "разниц", "задерж", "неправил", "отлича"]
        case .rankings: ["ranking", "rangliste", "platzierung", "leaderboard", "рейтинг", "мест"]
        case .flame: ["flamme", "serie", "streak", "flame", "огон", "огн", "сери"]
        case .groupFlame: ["gruppenflamme", "group flame", "огонь групп", "огня групп"]
        case .addFriends: ["freund", "friend", "друз", "друга", "друг$"]
        case .createGroup: ["gruppe", "group", "групп"]
        case .customizeHome: ["widget", "homescreen", "home$", "home screen", "anpass", "customiz", "виджет", "главн"]
        case .dailyGoal: ["tagesziel", "ziel", "goal", "цел"]
        case .editProfile: ["profil", "profile", "bio$", "banner", "interess", "interest", "профил", "обложк", "описани", "интерес"]
        case .privacy: ["datenschutz", "privatsph", "sichtbar", "privacy", "visib", "конфиденц", "видим", "приватн"]
        case .languageDesign: ["sprache", "design", "dunkel", "hell$", "helle$", "darstellung", "language", "dark", "light$", "appearance", "язык", "темн", "светл", "оформлен"]
        case .reportUser: ["nutzer melden", "melde", "blockier", "report user", "report a user", "block", "пожалов", "заблок", "жалоб"]
        case .reportBug: ["fehler", "bug", "absturz", "abgestürzt", "technisch", "support", "problem", "crash", "error", "technical", "ошибк", "поддержк", "сбой", "проблем", "техническ", "вылет"]
        }
    }

    /// Wörter, bei denen das Thema **nicht** passt (keine Antwort statt einer falschen): Freunde entfernen und Gruppen
    /// verlassen oder ändern deckt der Katalog nicht ab.
    var exclusions: [String] {
        switch self {
        case .addFriends: ["entfern", "lösch", "remove", "delete", "unfriend", "удал"]
        case .createGroup: ["verlass", "austret", "leave", "покин", "выйти", "выход", "entfern", "lösch", "remove", "delete", "удал", "änder", "change", "измен"]
        default: []
        }
    }
}

/// Ein Eintrag im Verlauf des Pace-Bots. Gespeichert werden Themen statt Texte (Sprachwechsel).
public struct PaceHelpMessage: Codable, Equatable, Sendable, Identifiable {
    public enum Role: String, Codable, Sendable {
        case bot
        case user
    }

    public enum Content: Codable, Equatable, Sendable {
        case greeting
        /// Vom Nutzer gewählte Frage.
        case question(PaceHelpTopic)
        case answer(PaceHelpTopic)
        /// Freie Eingabe des Nutzers (nur auf dem Gerät).
        case typed(String)
        /// Keine passende Antwort.
        case unknown
    }

    public let id: UUID
    public let role: Role
    public let content: Content
    public let date: Date

    public init(id: UUID = UUID(), role: Role, content: Content, date: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.date = date
    }

    public var text: String {
        switch content {
        case .greeting: PaceHelpBot.greeting
        case .question(let topic): topic.question
        case .answer(let topic): topic.answer
        case .typed(let text): text
        case .unknown: PaceHelpBot.unknownAnswer
        }
    }

    public var topic: PaceHelpTopic? {
        if case .answer(let topic) = content { return topic }
        return nil
    }
}

public enum PaceHelpBot {
    public static var name: String { PaceLocalization.text(de: "Pace-Bot", en: "Pace Bot", ru: "Pace-бот") }

    public static var subtitle: String {
        PaceLocalization.text(de: "Fragen rund um Pace? Ich helfe dir.", en: "Questions about Pace? I can help.", ru: "Вопросы о Pace? Я помогу.")
    }

    /// Hinweis, dass es eine automatische Hilfe ist (kein Mensch, keine KI).
    public static var automatedNote: String {
        PaceLocalization.text(
            de: "Automatische Hilfe mit vorbereiteten Antworten – kein Live-Chat mit Mitarbeitern.",
            en: "Automated help with prepared answers – not a live chat with staff.",
            ru: "Автоматическая помощь с готовыми ответами – это не чат с сотрудниками."
        )
    }

    public static var greeting: String {
        PaceLocalization.text(
            de: "Hey! 👋 Ich bin der Pace-Bot.\n\nIch helfe dir bei den wichtigsten Fragen rund um Pace.\n\nWobei brauchst du Hilfe?",
            en: "Hey! 👋 I'm Pace Bot.\n\nI help you with the most important questions about Pace.\n\nWhat do you need help with?",
            ru: "Привет! 👋 Я Pace-бот.\n\nЯ помогу с главными вопросами о Pace.\n\nС чем тебе помочь?"
        )
    }

    public static var unknownAnswer: String {
        PaceLocalization.text(
            de: "Dazu habe ich leider noch keine passende Antwort. Du kannst eine andere Frage auswählen oder unser Support-Team kontaktieren.",
            en: "Sorry, I don't have a matching answer for that yet. You can choose another question or contact our support team.",
            ru: "К сожалению, у меня пока нет подходящего ответа. Выбери другой вопрос или свяжись с нашей поддержкой."
        )
    }

    /// Höchstens so viele Zeichen je freier Eingabe.
    public static let maximumInputLength = 200

    /// Ordnet eine freie Eingabe einem Thema zu – nur, wenn das eindeutig ist; sonst `nil` (ehrliche Antwort statt
    /// erfundener).
    public static func match(_ input: String) -> PaceHelpTopic? {
        let tokens = Self.words(in: input)
        guard tokens.joined().count >= 3 else { return nil }
        var scores: [PaceHelpTopic: Int] = [:]
        for topic in PaceHelpTopic.allCases where !topic.exclusions.contains(where: { Self.contains(tokens, $0) }) {
            // Längere, genauere Stichwörter wiegen mehr („gruppenflamme“ vor „flamme“).
            let score = topic.keywords.filter { Self.contains(tokens, $0) }.reduce(0) { $0 + $1.filter(\.isLetter).count }
            if score > 0 { scores[topic] = score }
        }
        // Feste Vorränge bei Themen, die sich überschneiden.
        if scores[.groupFlame] != nil || (scores[.flame] != nil && scores[.createGroup] != nil) { return .groupFlame }
        if scores[.stepMismatch] != nil { scores[.stepCounting] = nil }
        if scores[.reportBug] != nil { scores[.reportUser] = nil }
        guard let best = scores.values.max() else { return nil }
        let leaders = scores.filter { $0.value == best }
        return leaders.count == 1 ? leaders.first?.key : nil
    }

    /// Wörter der Eingabe: klein, ohne Satzzeichen und Anführungszeichen, „ё“ als „е“.
    static func words(in input: String) -> [String] {
        input.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    /// Ob die Wortfolge des Stichworts in der Eingabe vorkommt (jedes Wort als Wortanfang, mit `$` als ganzes Wort).
    static func contains(_ words: [String], _ keyword: String) -> Bool {
        let parts = keyword.split(separator: " ").map(String.init)
        guard !parts.isEmpty, words.count >= parts.count else { return false }
        return (0...(words.count - parts.count)).contains { start in
            parts.indices.allSatisfy { offset in
                let word = words[start + offset], part = parts[offset]
                return part.hasSuffix("$") ? word == String(part.dropLast()) : word.hasPrefix(part)
            }
        }
    }
}

/// Verlauf des Pace-Bots (nur auf dem Gerät, begrenzt).
public protocol PaceHelpHistoryStoring: Sendable {
    func load() -> [PaceHelpMessage]
    func save(_ messages: [PaceHelpMessage])
}

public struct UserDefaultsPaceHelpHistoryStore: PaceHelpHistoryStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "pace.helpBot.history") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [PaceHelpMessage] {
        guard let data = defaults.data(forKey: key), let messages = try? JSONDecoder().decode([PaceHelpMessage].self, from: data) else { return [] }
        return messages
    }

    public func save(_ messages: [PaceHelpMessage]) {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        defaults.set(data, forKey: key)
    }
}

public final class InMemoryPaceHelpHistoryStore: PaceHelpHistoryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [PaceHelpMessage]

    public init(_ messages: [PaceHelpMessage] = []) {
        self.messages = messages
    }

    public func load() -> [PaceHelpMessage] { lock.withLock { messages } }
    public func save(_ messages: [PaceHelpMessage]) { lock.withLock { self.messages = messages } }
}

/// Gespräch mit dem Pace-Bot: vorgefertigte Fragen, einfache Stichworterkennung, ehrliche Antwort bei Unklarem.
@MainActor
@Observable
public final class PaceHelpBotSession {
    public private(set) var messages: [PaceHelpMessage] = []

    /// Höchstens so viele Einträge bleiben gespeichert (älteste fallen weg).
    public static let historyLimit = 60

    @ObservationIgnored private let store: any PaceHelpHistoryStoring
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(store: any PaceHelpHistoryStoring = InMemoryPaceHelpHistoryStore(), now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.now = now
        messages = store.load()
    }

    /// Beim ersten Öffnen: Begrüßung (einmal, nicht bei jedem Öffnen und nie beim bloßen Tabwechsel).
    public func start() {
        guard messages.isEmpty else { return }
        append(PaceHelpMessage(role: .bot, content: .greeting, date: now()))
    }

    /// Eine vorgefertigte Frage: erscheint als Nutzerblase, danach die hinterlegte Antwort.
    public func ask(_ topic: PaceHelpTopic) {
        let date = now()
        append(PaceHelpMessage(role: .user, content: .question(topic), date: date))
        append(PaceHelpMessage(role: .bot, content: .answer(topic), date: date))
    }

    /// Freie Eingabe: Stichworterkennung, sonst ehrlich „keine passende Antwort“.
    /// - Returns: Das erkannte Thema (`nil` = unbekannt) bzw. `nil` bei leerer Eingabe.
    @discardableResult
    public func send(_ input: String) -> PaceHelpTopic? {
        let text = String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(PaceHelpBot.maximumInputLength))
        guard !text.isEmpty else { return nil }
        let date = now()
        append(PaceHelpMessage(role: .user, content: .typed(text), date: date))
        let topic = PaceHelpBot.match(text)
        append(PaceHelpMessage(role: .bot, content: topic.map { .answer($0) } ?? .unknown, date: date))
        return topic
    }

    /// Verlauf zurücksetzen (danach wieder die Begrüßung).
    public func reset() {
        messages = []
        store.save([])
        start()
    }

    /// Ob die letzte Antwort „keine passende Antwort“ war (dann den Support anbieten).
    public var lastAnswerWasUnknown: Bool {
        messages.last?.content == .unknown
    }

    private func append(_ message: PaceHelpMessage) {
        messages.append(message)
        if messages.count > Self.historyLimit {
            messages.removeFirst(messages.count - Self.historyLimit)
        }
        store.save(messages)
    }
}

/// Offizieller Support-Kontakt. Eine E-Mail-Adresse gibt es nur, wenn sie eingerichtet ist (Info.plist-Schlüssel
/// `PaceSupportEmail` aus `PACE_SUPPORT_EMAIL` in `Config/Pace.xcconfig`) – es wird nie eine Adresse erfunden. Immer
/// verfügbar ist „Problem melden“ in der App (Profil → Hilfe & Feedback).
public struct PaceSupportContact: Equatable, Sendable {
    public let email: String?

    public init(email: String?) {
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Nur eine plausible Adresse übernehmen (kein Platzhalter wie „$(PACE_SUPPORT_EMAIL)“).
        let isPlausible = trimmed.contains("@") && trimmed.contains(".") && !trimmed.contains("$") && !trimmed.contains(" ")
        self.email = isPlausible ? trimmed : nil
    }

    public static func fromInfoDictionary(_ info: [String: Any]) -> PaceSupportContact {
        PaceSupportContact(email: info["PaceSupportEmail"] as? String)
    }

    public static var subject: String {
        PaceLocalization.text(de: "Pace – Supportanfrage", en: "Pace – support request", ru: "Pace – запрос в поддержку")
    }

    /// Vorlage zum Bearbeiten – ohne Gesundheitsdaten, Chats oder Kennungen.
    public static var bodyTemplate: String {
        PaceLocalization.text(
            de: "Hallo Pace-Team,\n\nich benötige Hilfe bei folgendem Anliegen:\n\n[Hier Problem beschreiben]",
            en: "Hello Pace team,\n\nI need help with the following:\n\n[Describe the problem here]",
            ru: "Здравствуйте, команда Pace!\n\nМне нужна помощь со следующим:\n\n[Опишите проблему здесь]"
        )
    }

    /// `mailto:`-Link mit Betreff und Vorlage (der Nutzer bearbeitet die Nachricht vor dem Senden).
    public var mailURL: URL? {
        guard let email else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: Self.subject),
            URLQueryItem(name: "body", value: Self.bodyTemplate),
        ]
        return components.url
    }
}
