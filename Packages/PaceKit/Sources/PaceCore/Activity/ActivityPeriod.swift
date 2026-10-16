import Foundation

/// Zeiträume, für die Pace Bewegungsdaten auswertet.
public enum ActivityPeriod: Hashable, Sendable, CaseIterable {
    case today
    case yesterday
    /// ISO-Woche (Montag bis heute).
    case currentWeek
    /// Heute und die sechs Tage davor.
    case lastSevenDays

    /// Erster und letzter Tag des Zeitraums, bezogen auf `today`.
    public func dayRange(endingOn today: LocalDate, calendar: ActivityCalendar) -> ClosedRange<LocalDate> {
        switch self {
        case .today:
            today...today
        case .yesterday:
            calendar.adding(-1, to: today)...calendar.adding(-1, to: today)
        case .currentWeek:
            calendar.startOfWeek(containing: today)...today
        case .lastSevenDays:
            calendar.adding(-6, to: today)...today
        }
    }
}
