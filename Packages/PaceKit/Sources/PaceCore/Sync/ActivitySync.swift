import Foundation

/// Der einzige Gesundheitswert, der das iPhone verlässt: Wettbewerbsschritte eines Kalendertags.
public struct DailyCompetitionSteps: Hashable, Sendable, Codable {
    /// Lokaler Kalendertag des Geräts zum Zeitpunkt der Messung.
    public let date: LocalDate
    public let competitionSteps: Int

    public init(date: LocalDate, competitionSteps: Int) {
        self.date = date
        self.competitionSteps = competitionSteps
    }

    /// Obergrenze, die auch serverseitig geprüft wird.
    public static let maximumSteps = 200_000
}

public enum ActivitySyncError: Error, Equatable, Sendable {
    case notAuthenticated
    case rejected
    case network
    case unexpected(String)
}

/// Schreibt Tageswerte ins Backend (Upsert auf Nutzer + Tag).
public protocol ActivitySyncRepository: Sendable {
    func upsert(_ days: [DailyCompetitionSteps], for userID: UserID) async throws
}

/// Anlass einer Synchronisierung.
public enum ActivitySyncTrigger: Sendable, Equatable {
    case appStart
    case foreground
    case pullToRefresh
    /// HealthKit hat neue Daten gemeldet. Wird gedrosselt, weil das beim Gehen häufig passiert.
    case healthKitUpdate
}

/// Nimmt neue Tageswerte entgegen und synchronisiert sie bei Bedarf.
public protocol ActivitySyncing: Sendable {
    func submit(_ overview: ActivityOverview, trigger: ActivitySyncTrigger) async
    /// Sendet zurückgehaltene Werte sofort (z. B. bevor ein Ranking geladen wird).
    func flush() async
}
