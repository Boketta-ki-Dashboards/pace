import Foundation
import Observation

/// Der Social-Bereich: Freunde, Anfragen, Gruppen und Einladungen.
///
/// In diesem Stand sind die Bereiche vorbereitet, aber noch ohne Backend. Sie werden als „bald verfügbar“ angezeigt,
/// statt Funktionen vorzutäuschen. Mit Freundschaften und Gruppen (siehe docs/ARCHITECTURE.md) bekommt jeder Bereich
/// einen eigenen Zustand.
@MainActor
@Observable
public final class SocialViewModel {
    public struct Section: Identifiable, Equatable, Sendable {
        public enum Availability: Equatable, Sendable {
            case comingSoon
        }

        public let id: String
        public let title: String
        public let subtitle: String
        public let systemImage: String
        public let emptyTitle: String
        public let emptyMessage: String
        public let availability: Availability
    }

    public let sections: [Section] = [
        Section(
            id: "friends",
            title: "Freunde",
            subtitle: "Freunde hinzufügen und jeden Tag vergleichen",
            systemImage: "person.2",
            emptyTitle: "Noch keine Freunde",
            emptyMessage: "Füge Freunde hinzu und tritt in eurem eigenen Ranking gegeneinander an.",
            availability: .comingSoon
        ),
        Section(
            id: "requests",
            title: "Freundschaftsanfragen",
            subtitle: "Anfragen annehmen oder ablehnen",
            systemImage: "person.badge.plus",
            emptyTitle: "Keine offenen Anfragen",
            emptyMessage: "Neue Anfragen erscheinen hier.",
            availability: .comingSoon
        ),
        Section(
            id: "groups",
            title: "Gruppen",
            subtitle: "Klassen-, Arbeits- und eigene Gruppen",
            systemImage: "person.3",
            emptyTitle: "Noch keine Gruppen",
            emptyMessage: "Gründe eine Gruppe für deine Klasse, dein Team oder deine Crew – mit eigenem Ranking und "
                + "später auch Chat.",
            availability: .comingSoon
        ),
        Section(
            id: "invites",
            title: "Einladungen",
            subtitle: "Per Link oder Code einladen",
            systemImage: "envelope.open",
            emptyTitle: "Keine Einladungen",
            emptyMessage: "Einladungen zu Gruppen und Challenges landen hier.",
            availability: .comingSoon
        ),
    ]

    public init() {}
}
