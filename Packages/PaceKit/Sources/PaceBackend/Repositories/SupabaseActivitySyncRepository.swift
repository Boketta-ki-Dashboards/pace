import Foundation
import PaceCore
import PostgREST

/// Schreibt Wettbewerbsschritte per Upsert auf (Nutzer, Tag) in `public.daily_activity`.
struct SupabaseActivitySyncRepository: ActivitySyncRepository {
    let client: PostgrestClient
    let tokens: AccessTokenProvider

    func upsert(_ days: [DailyCompetitionSteps], for userID: UserID) async throws {
        let rows = Self.rows(for: days, userID: userID)
        guard !rows.isEmpty else { return }
        do {
            try await client
                .from("daily_activity")
                .upsert(rows, onConflict: "user_id,activity_date", returning: .minimal)
                .execute()
        } catch {
            throw BackendErrorMapping.activitySyncError(error, hasSession: tokens.hasSession())
        }
    }

    /// Ein Eintrag je Tag (der letzte gewinnt), Schritte auf den erlaubten Bereich begrenzt, chronologisch.
    /// Doppelte Tage würden den Upsert sonst als Ganzes scheitern lassen.
    static func rows(for days: [DailyCompetitionSteps], userID: UserID) -> [DailyActivityRow] {
        var stepsByDay: [LocalDate: Int] = [:]
        for day in days {
            stepsByDay[day.date] = min(max(day.competitionSteps, 0), DailyCompetitionSteps.maximumSteps)
        }
        return stepsByDay
            .sorted { $0.key < $1.key }
            .map { DailyActivityRow(userID: userID.description, activityDate: $0.key.isoString, competitionSteps: $0.value) }
    }
}
