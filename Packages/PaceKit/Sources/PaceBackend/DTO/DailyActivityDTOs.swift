import Foundation

/// Zeile für `public.daily_activity`. Gesendet werden nur Wettbewerbsschritte – keine weiteren Gesundheitsdaten.
struct DailyActivityRow: Encodable, Equatable {
    let userID: String
    /// Lokaler Kalendertag im Format `YYYY-MM-DD`.
    let activityDate: String
    let competitionSteps: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case activityDate = "activity_date"
        case competitionSteps = "competition_steps"
    }
}
