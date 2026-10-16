import Foundation

/// Zeitraum eines Rankings. Milestone 2 zeigt nur `daily` an; `weekly` (ISO-Woche, Montag–Sonntag) ist im Backend
/// bereits umgesetzt.
public enum LeaderboardPeriod: String, Codable, Sendable, CaseIterable {
    case daily
    case weekly
}

/// Welches Ranking geladen wird.
public struct LeaderboardQuery: Hashable, Sendable {
    /// Region beliebiger Ebene (Gemeinde, Kreis, Bundesland, Land).
    public let regionID: RegionID
    public let period: LeaderboardPeriod
    /// Stichtag; bei `weekly` ein beliebiger Tag der Woche.
    public let date: LocalDate

    public init(regionID: RegionID, period: LeaderboardPeriod, date: LocalDate) {
        self.regionID = regionID
        self.period = period
        self.date = date
    }
}

/// Eine Zeile im Ranking. Enthält ausschließlich öffentliche Felder.
public struct LeaderboardEntry: Equatable, Hashable, Sendable, Identifiable {
    public let rank: Int
    public let publicUserID: UUID
    public let username: String
    public let displayName: String
    public let competitionSteps: Int
    public let isCurrentUser: Bool

    public init(
        rank: Int,
        publicUserID: UUID,
        username: String,
        displayName: String,
        competitionSteps: Int,
        isCurrentUser: Bool
    ) {
        self.rank = rank
        self.publicUserID = publicUserID
        self.username = username
        self.displayName = displayName
        self.competitionSteps = competitionSteps
        self.isCurrentUser = isCurrentUser
    }

    public var id: UUID { publicUserID }
}

/// Ein Ausschnitt des Rankings (serverseitig sortiert und paginiert).
public struct LeaderboardPage: Equatable, Sendable {
    public let entries: [LeaderboardEntry]
    /// Anzahl aller Teilnehmer in diesem Ranking.
    public let totalParticipants: Int
    public let offset: Int
    public let limit: Int

    public init(entries: [LeaderboardEntry], totalParticipants: Int, offset: Int, limit: Int) {
        self.entries = entries
        self.totalParticipants = totalParticipants
        self.offset = offset
        self.limit = limit
    }

    public var hasMore: Bool {
        offset + entries.count < totalParticipants
    }
}

public enum LeaderboardError: Error, Equatable, Sendable {
    case notAuthenticated
    case unknownRegion
    case network
    case unexpected(String)
}

/// Serverseitige Rankings. Es werden nie alle Teilnehmer geladen.
public protocol LeaderboardRepository: Sendable {
    /// Plätze `offset + 1` bis `offset + limit`.
    func page(for query: LeaderboardQuery, offset: Int, limit: Int) async throws -> LeaderboardPage

    /// Der eigene Platz und bis zu `radius` Plätze darüber und darunter. Leer, wenn der Nutzer nicht im Ranking ist.
    func neighborhood(for query: LeaderboardQuery, radius: Int) async throws -> [LeaderboardEntry]
}
