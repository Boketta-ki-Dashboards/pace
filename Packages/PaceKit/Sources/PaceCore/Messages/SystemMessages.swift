import Foundation
import Observation

/// Interne Systemmitteilung im Mitteilungscenter (Glocke auf Home) – keine Push-Benachrichtigung, kein Server.
public struct SystemMessage: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// „Willkommen bei Pace! 👋“ – einmal je Profil (auch für bestehende Nutzer nach dem Update).
        case welcome
    }

    public let kind: Kind
    public let createdAt: Date
    public var readAt: Date?

    public init(kind: Kind, createdAt: Date, readAt: Date? = nil) {
        self.kind = kind
        self.createdAt = createdAt
        self.readAt = readAt
    }

    public var id: String { "system-\(kind.rawValue)" }
    public var isRead: Bool { readAt != nil }

    public var sender: String {
        PaceLocalization.text(de: "Pace Team", en: "Pace Team", ru: "Команда Pace")
    }

    public var title: String {
        switch kind {
        case .welcome: PaceLocalization.text(de: "Willkommen bei Pace! 👋", en: "Welcome to Pace! 👋", ru: "Добро пожаловать в Pace! 👋")
        }
    }

    public var preview: String {
        switch kind {
        case .welcome:
            PaceLocalization.text(
                de: "Entdecke deine Schritte, erreiche Tagesziele, vergleiche dich mit Freunden und starte gemeinsame Challenges.",
                en: "Discover your steps, reach daily goals, compare yourself with friends and start challenges together.",
                ru: "Следи за шагами, достигай дневных целей, соревнуйся с друзьями и начинай общие челленджи."
            )
        }
    }
}

/// Gespeicherter Stand der Systemmitteilungen eines Profils.
public struct SystemMessageState: Codable, Equatable, Sendable {
    /// Schon einmal zugestellte Arten – auch nach dem Löschen wird keine zweite Kopie angelegt.
    public var delivered: Set<SystemMessage.Kind>
    public var messages: [SystemMessage]

    public init(delivered: Set<SystemMessage.Kind> = [], messages: [SystemMessage] = []) {
        self.delivered = delivered
        self.messages = messages
    }
}

/// Speicher der Systemmitteilungen je Profil (nur auf dem Gerät).
public protocol SystemMessageStoring: Sendable {
    func load(owner: String) -> SystemMessageState
    func save(_ state: SystemMessageState, owner: String)
}

/// UserDefaults (eine JSON-Zeile je Profil).
public struct UserDefaultsSystemMessageStore: SystemMessageStoring, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(owner: String) -> String { "pace.systemMessages.\(owner)" }

    public func load(owner: String) -> SystemMessageState {
        guard let data = defaults.data(forKey: Self.key(owner: owner)),
              let state = try? JSONDecoder().decode(SystemMessageState.self, from: data)
        else { return SystemMessageState() }
        return state
    }

    public func save(_ state: SystemMessageState, owner: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.key(owner: owner))
    }
}

/// Nur im Speicher (Tests, Vorschauen).
public final class InMemorySystemMessageStore: SystemMessageStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var states: [String: SystemMessageState] = [:]

    public init(_ states: [String: SystemMessageState] = [:]) {
        self.states = states
    }

    public func load(owner: String) -> SystemMessageState {
        lock.withLock { states[owner] ?? SystemMessageState() }
    }

    public func save(_ state: SystemMessageState, owner: String) {
        lock.withLock { states[owner] = state }
    }
}

/// Systemmitteilungen des angemeldeten Profils: einmalige Zustellung, gelesen, löschen.
@MainActor
@Observable
public final class SystemMessageCenter {
    public private(set) var messages: [SystemMessage] = []

    @ObservationIgnored private let store: any SystemMessageStoring
    @ObservationIgnored private var owner: String?
    @ObservationIgnored private var state = SystemMessageState()
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(store: any SystemMessageStoring = InMemorySystemMessageStore(), now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    public var unreadCount: Int {
        messages.filter { !$0.isRead }.count
    }

    /// Nach dem ersten vollständigen Einstieg (Profil angelegt): legt die Willkommensmitteilung genau einmal an – nicht
    /// bei jedem Start, Tabwechsel oder neuen Schritten. Bestehende Nutzer erhalten sie einmalig nach dem Update.
    /// - Parameter owner: Stabile Kennung des Profils (öffentliche ID) – ein anderes Konto auf dem Gerät hat eigene.
    public func activate(owner: String) {
        if self.owner != owner {
            self.owner = owner
            state = store.load(owner: owner)
        }
        if !state.delivered.contains(.welcome) {
            state.delivered.insert(.welcome)
            state.messages.append(SystemMessage(kind: .welcome, createdAt: now()))
            store.save(state, owner: owner)
        }
        messages = state.messages.sorted { $0.createdAt > $1.createdAt }
    }

    public func message(_ kind: SystemMessage.Kind) -> SystemMessage? {
        messages.first { $0.kind == kind }
    }

    /// Beim Öffnen als gelesen markieren.
    public func markRead(_ kind: SystemMessage.Kind) {
        guard let owner, let index = state.messages.firstIndex(where: { $0.kind == kind }), state.messages[index].readAt == nil else { return }
        state.messages[index].readAt = now()
        store.save(state, owner: owner)
        messages = state.messages.sorted { $0.createdAt > $1.createdAt }
    }

    /// Löscht die Mitteilung; sie wird nicht erneut angelegt.
    public func delete(_ kind: SystemMessage.Kind) {
        guard let owner else { return }
        state.messages.removeAll { $0.kind == kind }
        store.save(state, owner: owner)
        messages = state.messages.sorted { $0.createdAt > $1.createdAt }
    }
}

/// Inhalt der ausführlichen Willkommensmitteilung (Detailseite).
public enum WelcomeMessageContent {
    public struct Section: Equatable, Sendable, Identifiable {
        public let id: String
        public let systemImage: String
        public let title: String
        public let text: String
    }

    public static var intro: String {
        PaceLocalization.text(
            de: "Pace hilft dir dabei, Bewegung in deinen Alltag zu bringen und gemeinsam mit anderen aktiv zu bleiben.",
            en: "Pace helps you bring more movement into your everyday life and stay active together with others.",
            ru: "Pace помогает добавить больше движения в повседневную жизнь и оставаться активными вместе с другими."
        )
    }

    public static var sections: [Section] {
        [
            Section(
                id: "steps", systemImage: "shoeprints.fill",
                title: PaceLocalization.text(de: "Deine Schritte", en: "Your steps", ru: "Твои шаги"),
                text: PaceLocalization.text(
                    de: "Pace verwendet Apple Health, um deine Schritte automatisch zu erfassen. Du musst keine Schritte selbst eintragen.",
                    en: "Pace uses Apple Health to record your steps automatically. You don't have to enter any steps yourself.",
                    ru: "Pace использует Apple Health, чтобы автоматически учитывать твои шаги. Вводить шаги вручную не нужно."
                )
            ),
            Section(
                id: "goals", systemImage: "scope",
                title: PaceLocalization.text(de: "Deine Ziele", en: "Your goals", ru: "Твои цели"),
                text: PaceLocalization.text(
                    de: "Lege ein persönliches Tagesziel fest und beobachte deinen Fortschritt auf Home.",
                    en: "Set a personal daily goal and follow your progress on Home.",
                    ru: "Задай личную дневную цель и следи за прогрессом на вкладке «Главная»."
                )
            ),
            Section(
                id: "rankings", systemImage: "chart.bar.fill",
                title: PaceLocalization.text(de: "Rankings", en: "Rankings", ru: "Рейтинги"),
                text: PaceLocalization.text(
                    de: "Vergleiche dich mit anderen Nutzern in deiner Region oder mit deinen Freunden.",
                    en: "Compare yourself with other users in your region or with your friends.",
                    ru: "Сравнивай себя с другими пользователями в своём регионе или с друзьями."
                )
            ),
            Section(
                id: "friends", systemImage: "person.2.fill",
                title: PaceLocalization.text(de: "Freunde", en: "Friends", ru: "Друзья"),
                text: PaceLocalization.text(
                    de: "Füge Freunde hinzu, vergleicht eure Aktivität und bleibt über Chats miteinander in Kontakt.",
                    en: "Add friends, compare your activity and stay in touch through chats.",
                    ru: "Добавляй друзей, сравнивайте активность и общайтесь в чатах."
                )
            ),
            Section(
                id: "groups", systemImage: "person.3.fill",
                title: PaceLocalization.text(de: "Gruppen", en: "Groups", ru: "Группы"),
                text: PaceLocalization.text(
                    de: "Erstellt gemeinsame Gruppen, verfolgt euren Fortschritt und haltet eure Gruppenflamme am Leben.",
                    en: "Create groups together, follow your progress and keep your group flame alive.",
                    ru: "Создавайте группы, следите за общим прогрессом и поддерживайте огонь группы."
                )
            ),
            Section(
                id: "flame", systemImage: "flame.fill",
                title: PaceLocalization.text(de: "Deine Flamme", en: "Your flame", ru: "Твой огонь"),
                text: PaceLocalization.text(
                    de: "Erreiche dein Tagesziel regelmäßig, um persönliche Serien aufzubauen.",
                    en: "Reach your daily goal regularly to build personal streaks.",
                    ru: "Регулярно достигай дневной цели, чтобы строить личные серии."
                )
            ),
            Section(
                id: "home", systemImage: "square.grid.2x2.fill",
                title: PaceLocalization.text(de: "Dein Home", en: "Your Home", ru: "Твоя «Главная»"),
                text: PaceLocalization.text(
                    de: "Gestalte deine Übersicht mit Widgets nach deinen eigenen Wünschen.",
                    en: "Design your overview with widgets the way you like.",
                    ru: "Настраивай обзор с виджетами так, как тебе удобно."
                )
            ),
            Section(
                id: "help", systemImage: "questionmark.bubble.fill",
                title: PaceLocalization.text(de: "Brauchst du Hilfe?", en: "Need help?", ru: "Нужна помощь?"),
                text: PaceLocalization.text(
                    de: "Unser Pace-Bot beantwortet die wichtigsten Fragen rund um die App.",
                    en: "Our Pace Bot answers the most important questions about the app.",
                    ru: "Наш Pace-бот отвечает на главные вопросы о приложении."
                )
            ),
        ]
    }

    public static var exploreHome: String { PaceLocalization.text(de: "Home entdecken", en: "Explore Home", ru: "Перейти на «Главную»") }
    public static var openRankings: String { PaceLocalization.text(de: "Rankings ansehen", en: "View rankings", ru: "Смотреть рейтинги") }
    public static var addFriends: String { PaceLocalization.text(de: "Freunde hinzufügen", en: "Add friends", ru: "Добавить друзей") }
    public static var openHelpBot: String { PaceLocalization.text(de: "Pace-Bot öffnen", en: "Open Pace Bot", ru: "Открыть Pace-бота") }
    public static var delete: String { PaceLocalization.text(de: "Mitteilung löschen", en: "Delete notification", ru: "Удалить уведомление") }
}
