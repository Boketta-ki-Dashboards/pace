import Foundation

// MARK: - Personen

/// Öffentliche Angaben einer Person in Social-Funktionen. Nie Auth-ID, Gemeinde oder andere Gesundheitsdaten.
public struct SocialProfile: Equatable, Hashable, Sendable, Identifiable {
    public let publicID: UUID
    public let username: String
    public let displayName: String
    /// Profilbild im Bucket `avatars`; `nil` zeigt Initialen.
    public let avatarPath: String?

    public init(publicID: UUID, username: String, displayName: String, avatarPath: String? = nil) {
        self.publicID = publicID
        self.username = username
        self.displayName = displayName
        self.avatarPath = avatarPath
    }

    public var id: UUID { publicID }

    public var avatar: MediaReference? { .avatar(avatarPath) }
}

/// Beziehung zur gefundenen Person.
public enum SocialRelationship: String, Sendable {
    case me = "self"
    case friend
    case outgoingRequest = "outgoing_request"
    case incomingRequest = "incoming_request"
    case none
}

/// Treffer der Suche nach einem Benutzernamen.
public struct ProfileSearchResult: Equatable, Sendable, Identifiable {
    public let profile: SocialProfile
    public let relationship: SocialRelationship
    /// Offene Anfrage zwischen beiden (zum Annehmen bzw. Zurückziehen).
    public let requestID: UUID?

    public init(profile: SocialProfile, relationship: SocialRelationship, requestID: UUID?) {
        self.profile = profile
        self.relationship = relationship
        self.requestID = requestID
    }

    public var id: UUID { profile.publicID }
}

/// Profil einer Person, die man über die Suche, eine Gruppe oder einen Chat kennt. Schritte nur unter Freunden.
public struct PublicProfile: Equatable, Sendable {
    public let profile: SocialProfile
    public let relationship: SocialRelationship
    /// Offene Anfrage zwischen beiden (zum Annehmen bzw. Zurückziehen).
    public let requestID: UUID?
    /// Nur unter Freunden.
    public let friendsSince: Date?
    /// Wettbewerbsschritte heute und in der laufenden Woche – nur unter Freunden.
    public let stepsToday: Int?
    public let stepsWeek: Int?
    /// Du hast diese Person blockiert.
    public let isBlockedByMe: Bool

    public init(
        profile: SocialProfile,
        relationship: SocialRelationship,
        requestID: UUID?,
        friendsSince: Date?,
        stepsToday: Int?,
        stepsWeek: Int?,
        isBlockedByMe: Bool
    ) {
        self.profile = profile
        self.relationship = relationship
        self.requestID = requestID
        self.friendsSince = friendsSince
        self.stepsToday = stepsToday
        self.stepsWeek = stepsWeek
        self.isBlockedByMe = isBlockedByMe
    }
}

/// Was gemeldet wird.
public enum ReportTarget: Equatable, Sendable {
    case user(publicID: UUID)
    case message(id: UUID)
    case group(id: UUID)
}

/// Grund einer Meldung.
public enum ReportReason: String, CaseIterable, Sendable, Identifiable {
    case spam
    case harassment
    case inappropriate
    case impersonation
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .spam: PaceLocalization.text(de: "Spam", en: "Spam", ru: "Спам")
        case .harassment: PaceLocalization.text(de: "Belästigung oder Mobbing", en: "Harassment or bullying", ru: "Оскорбления или травля")
        case .inappropriate: PaceLocalization.text(de: "Unangemessene Inhalte", en: "Inappropriate content", ru: "Неприемлемый контент")
        case .impersonation: PaceLocalization.text(de: "Gibt sich als jemand anderes aus", en: "Impersonation", ru: "Выдаёт себя за другого")
        case .other: PaceLocalization.text(de: "Anderer Grund", en: "Other reason", ru: "Другая причина")
        }
    }
}

public struct FriendRequest: Equatable, Sendable, Identifiable {
    public enum Direction: String, Sendable {
        case incoming
        case outgoing
    }

    public let id: UUID
    public let direction: Direction
    public let profile: SocialProfile
    public let createdAt: Date

    public init(id: UUID, direction: Direction, profile: SocialProfile, createdAt: Date) {
        self.id = id
        self.direction = direction
        self.profile = profile
        self.createdAt = createdAt
    }
}

/// Ergebnis einer gesendeten Freundschaftsanfrage.
public enum FriendRequestOutcome: String, Sendable {
    /// Anfrage gesendet.
    case requested
    /// Die andere Person hatte bereits angefragt – ihr seid jetzt befreundet.
    case accepted
    case alreadyFriends = "already_friends"
    case alreadyRequested = "already_requested"
}

public struct Friend: Equatable, Sendable, Identifiable {
    public let profile: SocialProfile
    public let friendsSince: Date

    public init(profile: SocialProfile, friendsSince: Date) {
        self.profile = profile
        self.friendsSince = friendsSince
    }

    public var id: UUID { profile.publicID }
}

/// Profilansicht eines Freundes: nur Namen und Wettbewerbsschritte.
public struct FriendProfileDetails: Equatable, Sendable {
    public let profile: SocialProfile
    public let friendsSince: Date
    public let stepsToday: Int
    public let stepsWeek: Int

    public init(profile: SocialProfile, friendsSince: Date, stepsToday: Int, stepsWeek: Int) {
        self.profile = profile
        self.friendsSince = friendsSince
        self.stepsToday = stepsToday
        self.stepsWeek = stepsWeek
    }
}

// MARK: - Gruppen

public enum GroupKind: String, CaseIterable, Sendable, Identifiable {
    case friends
    case schoolClass = "class"
    case work
    case club
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .friends: PaceLocalization.text(de: "Freunde", en: "Friends", ru: "Друзья")
        case .schoolClass: PaceLocalization.text(de: "Klasse", en: "Class", ru: "Класс")
        case .work: PaceLocalization.text(de: "Arbeit", en: "Work", ru: "Работа")
        case .club: PaceLocalization.text(de: "Verein", en: "Club", ru: "Клуб")
        case .other: PaceLocalization.text(de: "Sonstige", en: "Other", ru: "Другое")
        }
    }

    /// Arten, die beim Erstellen angeboten werden (ältere Gruppen können auch `club`/`other` sein).
    public static let selectable: [GroupKind] = [.friends, .schoolClass, .work]

    public var systemImage: String {
        switch self {
        case .friends: "person.2.fill"
        case .schoolClass: "graduationcap.fill"
        case .work: "briefcase.fill"
        case .club: "sportscourt.fill"
        case .other: "person.3.fill"
        }
    }
}

public enum GroupRole: String, Sendable {
    case owner
    case member
}

/// Wer einer Gruppe beitreten kann. Gruppen sind nie öffentlich auffindbar.
public enum GroupPrivacy: String, CaseIterable, Sendable, Identifiable {
    /// Nur auf Einladung eines Mitglieds; der Einladungscode ist abgeschaltet.
    case inviteOnly = "invite_only"
    /// Auf Einladung oder mit dem Einladungscode.
    case code

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inviteOnly: PaceLocalization.text(de: "Privat", en: "Private", ru: "Закрытая")
        case .code: PaceLocalization.text(de: "Mit Einladungscode", en: "With invite code", ru: "По коду приглашения")
        }
    }

    public var explanation: String {
        switch self {
        case .inviteOnly:
            PaceLocalization.text(
                de: "Nur eingeladene Freunde können beitreten.",
                en: "Only invited friends can join.",
                ru: "Вступить могут только приглашённые друзья."
            )
        case .code:
            PaceLocalization.text(
                de: "Eingeladene Freunde und alle, die den Code kennen, können beitreten.",
                en: "Invited friends and anyone with the code can join.",
                ru: "Вступить могут приглашённые друзья и все, у кого есть код."
            )
        }
    }
}

/// Eine Gruppe aus Sicht eines Mitglieds, inklusive der serverseitig berechneten Gruppen-Streak.
///
/// Gruppentag = Kalendertag in der Zeitzone der Gruppe. Ein Tag gilt als erreicht, wenn mindestens ein Drittel der
/// Mitglieder (aufgerundet) das Gruppenziel erreicht hat.
public struct GroupSummary: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let description: String
    public let kind: GroupKind
    public let role: GroupRole
    public let memberCount: Int
    /// Ziel des heutigen Gruppentags.
    public let dailyGoal: Int
    /// Ab morgen geplantes, abweichendes Ziel.
    public let nextDailyGoal: Int?
    public let timeZone: String
    public let groupToday: LocalDate
    public let inviteCode: String
    public let currentStreak: Int
    public let bestStreak: Int
    public let todayReachedCount: Int
    public let todayRequiredCount: Int
    public let todayComplete: Bool
    public let createdAt: Date
    /// Gruppenbild im Bucket `group-images`.
    public let imagePath: String?
    public let privacy: GroupPrivacy

    public init(
        id: UUID,
        name: String,
        description: String,
        kind: GroupKind,
        role: GroupRole,
        memberCount: Int,
        dailyGoal: Int,
        nextDailyGoal: Int?,
        timeZone: String,
        groupToday: LocalDate,
        inviteCode: String,
        currentStreak: Int,
        bestStreak: Int,
        todayReachedCount: Int,
        todayRequiredCount: Int,
        todayComplete: Bool,
        createdAt: Date,
        imagePath: String? = nil,
        privacy: GroupPrivacy = .code
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.kind = kind
        self.role = role
        self.memberCount = memberCount
        self.dailyGoal = dailyGoal
        self.nextDailyGoal = nextDailyGoal
        self.timeZone = timeZone
        self.groupToday = groupToday
        self.inviteCode = inviteCode
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
        self.todayReachedCount = todayReachedCount
        self.todayRequiredCount = todayRequiredCount
        self.todayComplete = todayComplete
        self.createdAt = createdAt
        self.imagePath = imagePath
        self.privacy = privacy
    }

    public var isOwner: Bool { role == .owner }

    public var image: MediaReference? { .groupImage(imagePath) }
}

/// Wie viele Mitglieder ihr Ziel erreichen müssen: ein Drittel, aufgerundet (3 → 1, 6 → 2, 10 → 4, 20 → 7).
/// Maßgeblich ist die Berechnung auf dem Server; diese Funktion dient der Anzeige und den Tests.
public enum GroupStreakRules {
    public static func requiredMembers(forMemberCount count: Int) -> Int {
        count <= 0 ? 0 : (count + 2) / 3
    }
}

public struct GroupRankingEntry: Equatable, Sendable, Identifiable {
    public let rank: Int
    public let profile: SocialProfile
    public let competitionSteps: Int
    public let isCurrentUser: Bool
    public let role: GroupRole
    public let reachedGoalToday: Bool

    public init(
        rank: Int,
        profile: SocialProfile,
        competitionSteps: Int,
        isCurrentUser: Bool,
        role: GroupRole,
        reachedGoalToday: Bool
    ) {
        self.rank = rank
        self.profile = profile
        self.competitionSteps = competitionSteps
        self.isCurrentUser = isCurrentUser
        self.role = role
        self.reachedGoalToday = reachedGoalToday
    }

    public var id: UUID { profile.publicID }
}

public struct GroupRanking: Equatable, Sendable {
    public let totalParticipants: Int
    public let groupToday: LocalDate
    public let dailyGoal: Int
    public let entries: [GroupRankingEntry]

    public init(totalParticipants: Int, groupToday: LocalDate, dailyGoal: Int, entries: [GroupRankingEntry]) {
        self.totalParticipants = totalParticipants
        self.groupToday = groupToday
        self.dailyGoal = dailyGoal
        self.entries = entries
    }
}

/// Ergebnis eines Gruppentags (für die Streak-Übersicht).
public struct GroupDay: Equatable, Sendable, Identifiable {
    public let day: LocalDate
    public let memberCount: Int
    public let requiredCount: Int
    public let reachedCount: Int
    public let dailyGoal: Int
    public let reached: Bool
    public let isToday: Bool

    public init(
        day: LocalDate,
        memberCount: Int,
        requiredCount: Int,
        reachedCount: Int,
        dailyGoal: Int,
        reached: Bool,
        isToday: Bool
    ) {
        self.day = day
        self.memberCount = memberCount
        self.requiredCount = requiredCount
        self.reachedCount = reachedCount
        self.dailyGoal = dailyGoal
        self.reached = reached
        self.isToday = isToday
    }

    public var id: LocalDate { day }
}

/// Eingehende Einladung in eine Gruppe.
public struct GroupInvitation: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let groupID: UUID
    public let groupName: String
    public let groupKind: GroupKind
    public let memberCount: Int
    public let inviterUsername: String
    public let inviterDisplayName: String
    public let createdAt: Date
    public let groupImagePath: String?

    public init(
        id: UUID,
        groupID: UUID,
        groupName: String,
        groupKind: GroupKind,
        memberCount: Int,
        inviterUsername: String,
        inviterDisplayName: String,
        createdAt: Date,
        groupImagePath: String? = nil
    ) {
        self.id = id
        self.groupID = groupID
        self.groupName = groupName
        self.groupKind = groupKind
        self.memberCount = memberCount
        self.inviterUsername = inviterUsername
        self.inviterDisplayName = inviterDisplayName
        self.createdAt = createdAt
        self.groupImagePath = groupImagePath
    }
}

/// Offene Einladung, die aus einer Gruppe verschickt wurde.
public struct OutgoingGroupInvitation: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let profile: SocialProfile
    public let createdAt: Date

    public init(id: UUID, profile: SocialProfile, createdAt: Date) {
        self.id = id
        self.profile = profile
        self.createdAt = createdAt
    }
}

public enum GroupInviteOutcome: String, Sendable {
    case invited
    case alreadyMember = "already_member"
    case alreadyInvited = "already_invited"
}

/// Neue oder geänderte Gruppe.
public struct GroupDraft: Equatable, Sendable {
    public var name: String
    public var description: String
    public var kind: GroupKind
    public var dailyGoal: Int
    public var privacy: GroupPrivacy
    /// Freunde, die beim Erstellen eingeladen werden (öffentliche IDs).
    public var inviteePublicIDs: [UUID]

    public init(
        name: String = "",
        description: String = "",
        kind: GroupKind = .friends,
        dailyGoal: Int = 8_000,
        privacy: GroupPrivacy = .inviteOnly,
        inviteePublicIDs: [UUID] = []
    ) {
        self.name = name
        self.description = description
        self.kind = kind
        self.dailyGoal = dailyGoal
        self.privacy = privacy
        self.inviteePublicIDs = inviteePublicIDs
    }

    public static let nameLength = 3...40
    public static let descriptionLength = 0...200

    /// Getrimmt; `nil`, wenn der Name zu kurz oder zu lang ist.
    public var validName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.nameLength.contains(trimmed.count) ? trimmed : nil
    }

    public var validDescription: String? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.descriptionLength.contains(trimmed.count) ? trimmed : nil
    }
}

// MARK: - Fehler und Repository

public enum SocialError: Error, Equatable, Sendable {
    case network
    case notAuthenticated
    /// Ziel existiert nicht oder ist nicht sichtbar.
    case notFound
    /// Nur für die Person, die die Gruppe verwaltet.
    case notAllowed
    case invalidName
    case invalidDescription
    case invalidGoal
    case invalidInput
    case selfRequest
    case rateLimited
    /// Nach einer Ablehnung kann vorübergehend keine neue Anfrage gesendet werden.
    case cooldown
    case limitReached
    case invalidInviteCode
    /// Eine der beiden Personen hat die andere blockiert.
    case blocked
    /// Nachricht zu lang oder leer.
    case invalidMessage
    /// In dieser Unterhaltung kann man nicht mehr schreiben (z. B. nach Ende der Freundschaft).
    case readOnly
    /// Die Social-Funktionen sind auf dem Server (noch) nicht eingerichtet.
    case unavailable
    case unexpected(String)

    /// Text für die Anzeige.
    public var message: String {
        switch self {
        case .network:
            PaceLocalization.text(
                de: "Keine Verbindung. Prüfe deine Internetverbindung und versuche es erneut.",
                en: "No connection. Check your internet connection and try again.",
                ru: "Нет соединения. Проверь подключение к интернету и попробуй снова."
            )
        case .notAuthenticated:
            PaceLocalization.text(de: "Du bist nicht angemeldet. Starte Pace neu.", en: "You are not signed in. Restart Pace.", ru: "Ты не вошёл в систему. Перезапусти Pace.")
        case .notFound:
            PaceLocalization.text(de: "Nicht gefunden oder nicht mehr verfügbar.", en: "Not found or no longer available.", ru: "Не найдено или больше недоступно.")
        case .notAllowed:
            PaceLocalization.text(
                de: "Das kann nur die Person, die die Gruppe verwaltet.",
                en: "Only the person who manages the group can do this.",
                ru: "Это может сделать только администратор группы."
            )
        case .invalidName:
            PaceLocalization.text(de: "Der Name muss 3 bis 40 Zeichen lang sein.", en: "The name must be 3 to 40 characters long.", ru: "Название должно содержать от 3 до 40 символов.")
        case .invalidDescription:
            PaceLocalization.text(
                de: "Die Beschreibung darf höchstens 200 Zeichen lang sein.",
                en: "The description can be at most 200 characters long.",
                ru: "Описание может содержать не более 200 символов."
            )
        case .invalidGoal:
            PaceLocalization.text(
                de: "Das Gruppenziel muss zwischen 1.000 und 100.000 Schritten liegen.",
                en: "The group goal must be between 1,000 and 100,000 steps.",
                ru: "Цель группы должна быть от 1 000 до 100 000 шагов."
            )
        case .invalidInput:
            PaceLocalization.text(de: "Die Eingabe ist ungültig.", en: "The input is invalid.", ru: "Неверный ввод.")
        case .selfRequest:
            PaceLocalization.text(de: "Das bist du selbst.", en: "That's you.", ru: "Это ты.")
        case .rateLimited:
            PaceLocalization.text(
                de: "Zu viele Versuche in kurzer Zeit. Bitte warte etwas und versuche es dann erneut.",
                en: "Too many attempts in a short time. Please wait a moment and try again.",
                ru: "Слишком много попыток за короткое время. Подожди немного и попробуй снова."
            )
        case .cooldown:
            PaceLocalization.text(
                de: "Du kannst dieser Person gerade keine neue Anfrage senden. Versuche es in ein paar Tagen erneut.",
                en: "You can't send this person a new request right now. Try again in a few days.",
                ru: "Сейчас нельзя отправить этому человеку новый запрос. Попробуй через несколько дней."
            )
        case .limitReached:
            PaceLocalization.text(
                de: "Das Limit ist erreicht (z. B. Mitglieder einer Gruppe oder Anzahl deiner Gruppen).",
                en: "The limit has been reached (e.g. members of a group or number of your groups).",
                ru: "Достигнут лимит (например, участников группы или количества твоих групп)."
            )
        case .invalidInviteCode:
            PaceLocalization.text(de: "Dieser Einladungscode ist ungültig.", en: "This invite code is invalid.", ru: "Этот код приглашения недействителен.")
        case .blocked:
            PaceLocalization.text(
                de: "Das ist nicht möglich, weil eine Blockierung besteht.",
                en: "This isn't possible because of a block.",
                ru: "Это невозможно из-за блокировки."
            )
        case .invalidMessage:
            PaceLocalization.text(
                de: "Die Nachricht ist leer oder zu lang (höchstens 2.000 Zeichen).",
                en: "The message is empty or too long (at most 2,000 characters).",
                ru: "Сообщение пустое или слишком длинное (не более 2 000 символов)."
            )
        case .readOnly:
            PaceLocalization.text(
                de: "In dieser Unterhaltung kannst du keine Nachrichten mehr senden.",
                en: "You can no longer send messages in this conversation.",
                ru: "В этом чате больше нельзя отправлять сообщения."
            )
        case .unavailable:
            PaceLocalization.text(
                de: "Freunde, Gruppen und Chats sind auf dem Server noch nicht eingerichtet.",
                en: "Friends, groups and chats are not set up on the server yet.",
                ru: "Друзья, группы и чаты ещё не настроены на сервере."
            )
        case .unexpected:
            PaceLocalization.text(de: "Etwas ist schiefgelaufen. Bitte versuche es erneut.", en: "Something went wrong. Please try again.", ru: "Что-то пошло не так. Попробуй снова.")
        }
    }
}

/// Freunde und Gruppen. Alle Prüfungen (Zugriff, Limits, Streak) erfolgen serverseitig.
public protocol SocialRepository: Sendable {
    func findProfile(username: String) async throws -> ProfileSearchResult?
    /// Personen, deren Benutzername mit `query` beginnt (mindestens 3 Zeichen, höchstens 20 Treffer). Exakte Treffer
    /// zuerst; Personen, die nicht in der Suche erscheinen möchten, nur bei exakter Eingabe; Blockierte nie.
    func searchProfiles(query: String) async throws -> [ProfileSearchResult]
    /// Profil einer bekannten Person (z. B. aus Suche, Gruppe oder Chat). Schritte nur unter Freunden.
    func publicProfile(_ publicID: UUID, date: LocalDate) async throws -> PublicProfile
    func sendFriendRequest(to publicID: UUID) async throws -> FriendRequestOutcome
    func respondToFriendRequest(_ requestID: UUID, accept: Bool) async throws
    func cancelFriendRequest(_ requestID: UUID) async throws
    func removeFriend(_ publicID: UUID) async throws
    func friendRequests() async throws -> [FriendRequest]
    func friends() async throws -> [Friend]
    /// Rangliste mit dir und deinen Freunden (gleiche Form wie Regionalrankings).
    func friendRanking(period: LeaderboardPeriod, date: LocalDate) async throws -> [LeaderboardEntry]
    func friendProfile(_ publicID: UUID, date: LocalDate) async throws -> FriendProfileDetails

    func createGroup(_ draft: GroupDraft, timeZone: String) async throws -> GroupSummary
    func updateGroup(_ groupID: UUID, name: String, description: String, kind: GroupKind) async throws -> GroupSummary
    /// Gilt ab dem nächsten Gruppentag.
    func setGroupGoal(_ groupID: UUID, dailyGoal: Int) async throws -> GroupSummary
    func myGroups() async throws -> [GroupSummary]
    func group(_ groupID: UUID) async throws -> GroupSummary
    func groupRanking(_ groupID: UUID, period: LeaderboardPeriod) async throws -> GroupRanking
    func groupDays(_ groupID: UUID, count: Int) async throws -> [GroupDay]
    func regenerateInviteCode(_ groupID: UUID) async throws -> GroupSummary
    func joinGroup(inviteCode: String) async throws -> GroupSummary
    func leaveGroup(_ groupID: UUID) async throws
    func removeMember(_ publicID: UUID, from groupID: UUID) async throws
    func deleteGroup(_ groupID: UUID) async throws
    func invite(_ publicID: UUID, to groupID: UUID) async throws -> GroupInviteOutcome
    func groupInvitations() async throws -> [GroupInvitation]
    func outgoingInvitations(for groupID: UUID) async throws -> [OutgoingGroupInvitation]
    func respondToInvitation(_ invitationID: UUID, accept: Bool) async throws -> GroupSummary?
    func cancelInvitation(_ invitationID: UUID) async throws

    // MARK: Gruppen (Erweiterungen)

    /// Name, Beschreibung, Art und Privatsphäre (nur wer die Gruppe verwaltet).
    func updateGroupDetails(_ groupID: UUID, name: String, description: String, kind: GroupKind, privacy: GroupPrivacy) async throws -> GroupSummary
    /// Setzt oder entfernt das Gruppenbild (Pfad im Bucket `group-images`, vorher hochgeladen).
    func setGroupImage(_ groupID: UUID, path: String?) async throws -> GroupSummary

    // MARK: Schutz

    /// Blockiert eine Person: Freundschaft, offene Anfragen und Einladungen zwischen euch enden; ihr findet euch nicht
    /// mehr und könnt euch nicht mehr schreiben.
    func block(_ publicID: UUID) async throws
    func unblock(_ publicID: UUID) async throws
    func blockedUsers() async throws -> [SocialProfile]
    /// Meldung an das Pace-Team (gespeichert, Bearbeitung außerhalb der App).
    func report(_ target: ReportTarget, reason: ReportReason, details: String?) async throws
}
