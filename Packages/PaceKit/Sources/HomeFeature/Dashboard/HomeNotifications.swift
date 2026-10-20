import Foundation
import PaceCore

/// Ein Eintrag unter „Mitteilungen“ – ausschließlich aus echten Social-Daten: eingehende Freundschaftsanfragen,
/// Gruppeneinladungen und Unterhaltungen mit ungelesenen Nachrichten.
public struct HomeNotificationItem: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case friendRequest(FriendRequest)
        case groupInvitation(GroupInvitation)
        case unreadChat(ConversationSummary)
    }

    public let kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    public var id: String {
        switch kind {
        case .friendRequest(let request): "request-\(request.id.uuidString)"
        case .groupInvitation(let invitation): "invitation-\(invitation.id.uuidString)"
        case .unreadChat(let conversation): "chat-\(conversation.id.uuidString)"
        }
    }

    public var date: Date {
        switch kind {
        case .friendRequest(let request): request.createdAt
        case .groupInvitation(let invitation): invitation.createdAt
        case .unreadChat(let conversation): conversation.updatedAt
        }
    }

    public var systemImage: String {
        switch kind {
        case .friendRequest: "person.badge.plus"
        case .groupInvitation: "person.3"
        case .unreadChat: "bubble.left.and.bubble.right"
        }
    }

    /// Name für das Profilbild bzw. die Initialen.
    public var avatarName: String {
        switch kind {
        case .friendRequest(let request): request.profile.displayName
        case .groupInvitation(let invitation): invitation.groupName
        case .unreadChat(let conversation): conversation.title
        }
    }

    /// Fester Schlüssel für die Farbe der Initialen.
    public var avatarSeed: String {
        switch kind {
        case .friendRequest(let request): request.profile.publicID.uuidString
        case .groupInvitation(let invitation): invitation.groupID.uuidString
        case .unreadChat(let conversation): conversation.peer?.publicID.uuidString ?? conversation.id.uuidString
        }
    }

    public var avatar: MediaReference? {
        switch kind {
        case .friendRequest(let request): request.profile.avatar
        case .groupInvitation(let invitation): .groupImage(invitation.groupImagePath)
        case .unreadChat(let conversation):
            conversation.peer?.avatar ?? .groupImage(conversation.groupImagePath)
        }
    }

    public var title: String {
        switch kind {
        case .friendRequest:
            PaceLocalization.text(de: "Freundschaftsanfrage", en: "Friend request", ru: "Запрос в друзья")
        case .groupInvitation:
            PaceLocalization.text(de: "Gruppeneinladung", en: "Group invitation", ru: "Приглашение в группу")
        case .unreadChat(let conversation):
            conversation.title
        }
    }

    public var message: String {
        switch kind {
        case .friendRequest(let request):
            let name = request.profile.displayName
            return PaceLocalization.text(
                de: "\(name) möchte mit dir befreundet sein.",
                en: "\(name) wants to be your friend.",
                ru: "\(name) хочет добавить тебя в друзья."
            )
        case .groupInvitation(let invitation):
            let name = invitation.inviterDisplayName
            let group = invitation.groupName
            return PaceLocalization.text(
                de: "\(name) hat dich in „\(group)“ eingeladen.",
                en: "\(name) invited you to “\(group)”.",
                ru: "\(name) приглашает тебя в «\(group)»."
            )
        case .unreadChat(let conversation):
            let count = conversation.unreadCount
            return "\(count.paceFormatted) " + PaceLocalization.plural(
                count,
                de: ("neue Nachricht", "neue Nachrichten"),
                en: ("new message", "new messages"),
                ru: ("новое сообщение", "новых сообщения", "новых сообщений")
            )
        }
    }
}

public enum HomeNotifications {
    /// Alle Einträge, neueste zuerst.
    public static func items(
        incomingRequests: [FriendRequest],
        invitations: [GroupInvitation],
        conversations: [ConversationSummary]
    ) -> [HomeNotificationItem] {
        let requests = incomingRequests.filter { $0.direction == .incoming }.map { HomeNotificationItem(kind: .friendRequest($0)) }
        let invites = invitations.map { HomeNotificationItem(kind: .groupInvitation($0)) }
        let chats = conversations.filter { $0.unreadCount > 0 }.map { HomeNotificationItem(kind: .unreadChat($0)) }
        return (requests + invites + chats).sorted { $0.date > $1.date }
    }

    /// VoiceOver-Name der Glocke, z. B. `Mitteilungen, 3 neu`.
    public static func bellAccessibilityLabel(count: Int) -> String {
        guard count > 0 else { return HomeTexts.notifications }
        return HomeTexts.notifications + ", " + PaceLocalization.plural(
            count,
            de: ("\(count) neu", "\(count) neu"),
            en: ("\(count) new", "\(count) new"),
            ru: ("\(count) новое", "\(count) новых", "\(count) новых")
        )
    }

    public static var emptyTitle: String {
        PaceLocalization.text(de: "Alles gelesen", en: "You're all caught up", ru: "Всё прочитано")
    }

    public static var emptyMessage: String {
        PaceLocalization.text(
            de: "Hier erscheinen Freundschaftsanfragen, Gruppeneinladungen und neue Nachrichten.",
            en: "Friend requests, group invitations and new messages will show up here.",
            ru: "Здесь появятся запросы в друзья, приглашения в группы и новые сообщения."
        )
    }

    public static var unavailableMessage: String {
        PaceLocalization.text(
            de: "Mitteilungen sind gerade nicht verfügbar.",
            en: "Notifications are unavailable right now.",
            ru: "Уведомления сейчас недоступны."
        )
    }
}
