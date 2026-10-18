import Foundation

// MARK: - Personen

/// Öffentliche Angaben einer Person in Social-Funktionen. Nie Auth-ID, Gemeinde oder andere Gesundheitsdaten.
public struct SocialProfile: Equatable, Hashable, Sendable, Identifiable {
    public let publicID: UUID
    public let username: String
    public let displayName: String

    public init(publicID: UUID, username: String, displayName: String) {
        self.publicID = publicID
        self.username = username
        self.displayName = displayName
    }

    public var id: UUID { publicID }
}

/// Beziehung zur gefundenen Person.
public enum SocialRelationship: String, Sendable {
    case me = "self"
    case friend
    case outgoingRequest = "outgoing_request"
    case incomingRequest = "incoming_request"
    case none
}

/// Treffer der Suche nach einem Benutzernamen (nur exakte Übereinstimmung).
public struct ProfileSearchResult: Equatable, Sendable {
    public let profile: SocialProfile
    public let relationship: SocialRelationship
    /// Offene Anfrage zwischen beiden (zum Annehmen bzw. Zurückziehen).
    public let requestID: UUID?

    public init(profile: SocialProfile, relationship: SocialRelationship, requestID: UUID?) {
        self.profile = profile
        self.relationship = relationship
        self.requestID = requestID
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
        case .friends: "Freunde"
        case .schoolClass: "Klasse"
        case .work: "Arbeit"
        case .club: "Verein"
        case .other: "Sonstige"
        }
    }

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
        createdAt: Date
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
    }

    public var isOwner: Bool { role == .owner }
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

    public init(
        id: UUID,
        groupID: UUID,
        groupName: String,
        groupKind: GroupKind,
        memberCount: Int,
        inviterUsername: String,
        inviterDisplayName: String,
        createdAt: Date
    ) {
        self.id = id
        self.groupID = groupID
        self.groupName = groupName
        self.groupKind = groupKind
        self.memberCount = memberCount
        self.inviterUsername = inviterUsername
        self.inviterDisplayName = inviterDisplayName
        self.createdAt = createdAt
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

    public init(name: String = "", description: String = "", kind: GroupKind = .friends, dailyGoal: Int = StepGoalRules.defaultGoal) {
        self.name = name
        self.description = description
        self.kind = kind
        self.dailyGoal = dailyGoal
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
    /// Die Social-Funktionen sind auf dem Server (noch) nicht eingerichtet.
    case unavailable
    case unexpected(String)

    /// Text für die Anzeige.
    public var message: String {
        switch self {
        case .network: "Keine Verbindung. Prüfe deine Internetverbindung und versuche es erneut."
        case .notAuthenticated: "Du bist nicht angemeldet. Starte Pace neu."
        case .notFound: "Nicht gefunden oder nicht mehr verfügbar."
        case .notAllowed: "Das kann nur die Person, die die Gruppe verwaltet."
        case .invalidName: "Der Name muss 3 bis 40 Zeichen lang sein."
        case .invalidDescription: "Die Beschreibung darf höchstens 200 Zeichen lang sein."
        case .invalidGoal: "Das Gruppenziel muss zwischen 1.000 und 100.000 Schritten liegen."
        case .invalidInput: "Die Eingabe ist ungültig."
        case .selfRequest: "Das bist du selbst."
        case .rateLimited: "Zu viele Versuche in kurzer Zeit. Bitte warte etwas und versuche es dann erneut."
        case .cooldown: "Du kannst dieser Person gerade keine neue Anfrage senden. Versuche es in ein paar Tagen erneut."
        case .limitReached: "Das Limit ist erreicht (z. B. Mitglieder einer Gruppe oder Anzahl deiner Gruppen)."
        case .invalidInviteCode: "Dieser Einladungscode ist ungültig."
        case .unavailable: "Freunde und Gruppen sind auf dem Server noch nicht eingerichtet."
        case .unexpected: "Etwas ist schiefgelaufen. Bitte versuche es erneut."
        }
    }
}

/// Freunde und Gruppen. Alle Prüfungen (Zugriff, Limits, Streak) erfolgen serverseitig.
public protocol SocialRepository: Sendable {
    func findProfile(username: String) async throws -> ProfileSearchResult?
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
}
