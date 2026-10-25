import Foundation
import Observation
import PaceCore

/// Ziel einer Navigation im Social-Tab.
public enum SocialRoute: Hashable, Sendable {
    case group(UUID)
    /// Profil einer Person (gleich wie ``profile(_:)``; bleibt für bestehende Aufrufer erhalten).
    case friend(SocialProfile)
    case profile(SocialProfile)
    case addFriend
    case requests
    case createGroup
    case groups
    case groupMembers(UUID)
    case groupSettings(UUID)
    case groupCalendar(UUID)
    case friendsRanking
    case settings
    case shareProfile(SocialProfile)
    case report(SocialReportSubject)

    /// Welche Seite die Route zeigt: Zwei Routen derselben Seite (z. B. `.friend` und `.profile` derselben Person, oder
    /// dieselbe Gruppe mit anderem Anzeigenamen) gelten als gleich. Gruppenseiten unterscheiden sich über die Gruppen-ID.
    var page: SocialPage {
        switch self {
        case .group(let id): .group(id)
        case .friend(let profile), .profile(let profile): .profile(profile.publicID)
        case .addFriend: .addFriend
        case .requests: .requests
        case .createGroup: .createGroup
        case .groups: .groups
        case .groupMembers(let id): .groupMembers(id)
        case .groupSettings(let id): .groupSettings(id)
        case .groupCalendar(let id): .groupCalendar(id)
        case .friendsRanking: .friendsRanking
        case .settings: .settings
        case .shareProfile(let profile): .shareProfile(profile.publicID)
        case .report(.user(let profile)): .reportUser(profile.publicID)
        case .report(.group(let id, _)): .reportGroup(id)
        }
    }
}

/// Identität einer Social-Seite (ohne Anzeigedaten wie Namen oder Spitznamen).
enum SocialPage: Hashable {
    case group(UUID)
    case groupMembers(UUID)
    case groupSettings(UUID)
    case groupCalendar(UUID)
    case profile(UUID)
    case shareProfile(UUID)
    case reportUser(UUID)
    case reportGroup(UUID)
    case addFriend
    case requests
    case createGroup
    case groups
    case friendsRanking
    case settings
}

/// Eintrag im Navigationspfad des Social-Tabs: eine Social-Seite oder ein Chat.
public enum SocialPathItem: Hashable, Sendable {
    case route(SocialRoute)
    case chat(ChatTarget)
}

/// Einzige Quelle für den Navigationspfad des Social-Tabs (Gruppen, Flamme, Kalender, Chats, Profile).
///
/// Jede Seite hat eine eindeutige Identität (Gruppen-ID, Person, Unterhaltung). Öffnet man eine Seite, die im Pfad
/// schon liegt, geht es zu ihr zurück, statt sie erneut aufzulegen (``PaceNavigationRules``). Damit kann der Wechsel
/// Gruppe → Chat → Flamme → Chat … den Stapel nicht mehr wachsen lassen, und doppeltes Tippen legt keine zweite Ebene
/// auf. Weil darunterliegende Seiten verschwinden, enden auch ihre Aufgaben (Laden, Echtzeit, Abfragen).
@MainActor
@Observable
public final class SocialNavigator {
    /// Pfad des `NavigationStack` (die Zurück-Geste des Systems schreibt ihn ebenfalls).
    public var path: [SocialPathItem] = [] {
        didSet { onPathChange?(path) }
    }

    /// Wird nach jeder Änderung des Pfads aufgerufen (z. B. um nicht mehr offene Chats freizugeben).
    @ObservationIgnored var onPathChange: (@MainActor ([SocialPathItem]) -> Void)?

    @ObservationIgnored private let isSameChat: @MainActor (ChatTarget, ChatTarget) -> Bool

    /// - Parameter isSameChat: Ob zwei Ziele dieselbe Unterhaltung zeigen (z. B. Gruppenchat über die Gruppe und über
    ///   die Chatliste). Ohne Angabe nach Gruppe, Person bzw. Unterhaltung (Namen zählen nicht).
    public init(isSameChat: @escaping @MainActor (ChatTarget, ChatTarget) -> Bool = SocialNavigator.sameChatTarget) {
        self.isSameChat = isSameChat
    }

    /// Gleiche Gruppe, gleiche Person bzw. gleiche Unterhaltung – ohne Wissen über geladene Unterhaltungen.
    public static func sameChatTarget(_ lhs: ChatTarget, _ rhs: ChatTarget) -> Bool {
        switch (lhs, rhs) {
        case (.group(let a, _), .group(let b, _)): a == b
        case (.direct(let a), .direct(let b)): a.publicID == b.publicID
        case (.conversation(let a, _, _), .conversation(let b, _, _)): a == b
        default: false
        }
    }

    public var isAtRoot: Bool { path.isEmpty }

    /// Chats im Pfad (offen oder darunter verdeckt).
    var chatTargets: [ChatTarget] {
        path.compactMap { item in
            if case .chat(let target) = item { target } else { nil }
        }
    }

    /// Öffnet eine Social-Seite – oder geht zu ihr zurück, wenn sie schon offen ist.
    public func open(_ route: SocialRoute) {
        go(to: .route(route))
    }

    /// Öffnet einen Chat – oder geht zu ihm zurück, wenn er schon offen ist.
    public func openChat(_ target: ChatTarget) {
        go(to: .chat(target))
    }

    /// Ersetzt die aktuelle Seite (z. B. „Gruppe erstellen“ → Details der neuen Gruppe).
    public func replaceTop(with route: SocialRoute) {
        set(PaceNavigationRules.replacingTop(with: .route(route), in: path, isSamePage: isSamePage))
    }

    /// Ersetzt die aktuelle Seite durch einen Chat (z. B. nach „Profil teilen“ an genau einen Chat).
    public func replaceTop(withChat target: ChatTarget) {
        set(PaceNavigationRules.replacingTop(with: .chat(target), in: path, isSamePage: isSamePage))
    }

    /// Ersetzt die oberste Seite nur, wenn sie noch `expected` ist (z. B. „Gruppe erstellen“ nach dem Erstellen). Hat
    /// die Person inzwischen woandershin navigiert, wird das Ziel normal geöffnet – keine fremde Seite verschwindet.
    public func replace(_ expected: SocialRoute, with route: SocialRoute) {
        if isTop(expected) {
            replaceTop(with: route)
        } else {
            open(route)
        }
    }

    /// Wie ``replace(_:with:)``, mit einem Chat als Ziel (z. B. nach „Profil teilen“ an genau einen Chat).
    public func replace(_ expected: SocialRoute, withChat target: ChatTarget) {
        if isTop(expected) {
            replaceTop(withChat: target)
        } else {
            openChat(target)
        }
    }

    /// Schließt alle Seiten einer Gruppe (nach Verlassen oder Löschen): Details, Mitglieder, Einstellungen, Kalender,
    /// Meldung und den Gruppenchat. Andere Seiten bleiben, in ihrer Reihenfolge.
    public func closeGroup(_ groupID: UUID) {
        set(path.filter { item in
            switch item {
            case .route(let route):
                switch route.page {
                case .group(let id), .groupMembers(let id), .groupSettings(let id), .groupCalendar(let id), .reportGroup(let id):
                    return id != groupID
                default:
                    return true
                }
            case .chat(let target):
                if case .group(let id, _) = target, id == groupID { return false }
                return !isSameChat(target, .group(id: groupID, name: ""))
            }
        })
    }

    private func isTop(_ route: SocialRoute) -> Bool {
        guard case .route(let top) = path.last else { return false }
        return top.page == route.page
    }

    /// Öffnet eine Seite von außen (geteilter Link, Home-Widget): genau diese Seite über der Hauptseite.
    public func show(_ route: SocialRoute) {
        set([.route(route)])
    }

    /// Gruppenkalender einer Gruppe von außen (z. B. Home-Widget): Gruppe darunter, damit Zurück zur Gruppe führt.
    public func showGroupCalendar(_ groupID: UUID) {
        set([.route(.group(groupID)), .route(.groupCalendar(groupID))])
    }

    /// Zurück zur Hauptseite.
    public func popToRoot() {
        set([])
    }

    /// Ob zwei Einträge dieselbe Seite zeigen.
    func isSamePage(_ lhs: SocialPathItem, _ rhs: SocialPathItem) -> Bool {
        switch (lhs, rhs) {
        case (.route(let a), .route(let b)): a.page == b.page
        case (.chat(let a), .chat(let b)): isSameChat(a, b)
        default: false
        }
    }

    private func go(to item: SocialPathItem) {
        set(PaceNavigationRules.opening(item, in: path, isSamePage: isSamePage))
    }

    /// Schreibt nur bei einer echten Änderung (kein unnötiges Neuzeichnen des Stapels).
    private func set(_ newPath: [SocialPathItem]) {
        if newPath != path {
            path = newPath
        }
    }
}
