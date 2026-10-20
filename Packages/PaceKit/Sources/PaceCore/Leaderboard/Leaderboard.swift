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
    /// Profilbild im Bucket `avatars`.
    public let avatarPath: String?

    public init(
        rank: Int,
        publicUserID: UUID,
        username: String,
        displayName: String,
        competitionSteps: Int,
        isCurrentUser: Bool,
        avatarPath: String? = nil
    ) {
        self.rank = rank
        self.publicUserID = publicUserID
        self.username = username
        self.displayName = displayName
        self.competitionSteps = competitionSteps
        self.isCurrentUser = isCurrentUser
        self.avatarPath = avatarPath
    }

    public var id: UUID { publicUserID }

    public var avatar: MediaReference? { .avatar(avatarPath) }
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

/// Gemeinsame Regeln für Aufstiegshinweise – auf Home („Dein Umfeld“) und im Rankings-Tab gleich.
public enum RankingHint {
    /// Schritte, die zum Platz darüber fehlen: Vordermann − eigene + 1, weil bei Gleichstand gewinnt, wer den Wert
    /// zuerst hatte. `nil` auf Platz 1 oder wenn der Platz darüber nicht geladen ist.
    public static func stepsToNextPlace(currentUser: LeaderboardEntry, above: LeaderboardEntry?) -> Int? {
        guard currentUser.rank > 1, let above, above.rank == currentUser.rank - 1 else { return nil }
        return max(above.competitionSteps - currentUser.competitionSteps + 1, 1)
    }

    /// Ob der Platz darüber gleich viele Schritte hat (Gleichstand – vorn steht, wer den Wert zuerst erreicht hat).
    public static func isTied(currentUser: LeaderboardEntry, above: LeaderboardEntry?) -> Bool {
        guard currentUser.rank > 1, let above, above.rank == currentUser.rank - 1 else { return false }
        return above.competitionSteps <= currentUser.competitionSteps
    }

    /// z. B. `Noch 280 Schritte bis Platz #11`, `Gleichstand mit Platz #11 – noch 1 Schritt zum Überholen`,
    /// `Du führst in Pfungstadt.` oder `Du bist der Erste in Pfungstadt.` – in der Sprache der App.
    /// `locative` ist die Ortsangabe passend zur Sprache (``Region/locative``).
    public static func text(currentUser: LeaderboardEntry, above: LeaderboardEntry?, isAlone: Bool, locative: String) -> String? {
        if isAlone {
            return PaceLocalization.text(
                de: "Du bist der Erste \(locative).",
                en: "You're the first one \(locative).",
                ru: "Ты первый \(locative)."
            )
        }
        if currentUser.rank == 1 {
            return PaceLocalization.text(
                de: "Du führst \(locative).",
                en: "You're in the lead \(locative).",
                ru: "Ты лидируешь \(locative)."
            )
        }
        guard let steps = stepsToNextPlace(currentUser: currentUser, above: above) else { return nil }
        let place = "#\((currentUser.rank - 1).paceFormatted)"
        let stepsText = PaceLocalization.steps(steps)
        let englishSteps = "\(steps.paceFormatted) more \(steps == 1 ? "step" : "steps")"
        if isTied(currentUser: currentUser, above: above) {
            return PaceLocalization.text(
                de: "Gleichstand mit Platz \(place) – noch \(stepsText) zum Überholen",
                en: "Tied with rank \(place) – \(englishSteps) to overtake",
                ru: "Столько же шагов, как у места \(place), – ещё \(stepsText), чтобы обогнать"
            )
        }
        return PaceLocalization.text(
            de: "Noch \(stepsText) bis Platz \(place)",
            en: "\(englishSteps) to rank \(place)",
            ru: "Ещё \(stepsText) до места \(place)"
        )
    }
}
