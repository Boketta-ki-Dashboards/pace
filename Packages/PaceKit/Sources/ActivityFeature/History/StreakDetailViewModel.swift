import Foundation
import Observation
import PaceCore

/// Flammen-Detailseite: Bericht für den angezeigten Monat und den ausgewählten Tag, Monatswechsel.
@MainActor
@Observable
public final class StreakDetailViewModel {
    public enum Content: Equatable {
        case loading
        case noReadAccess
        case failed(String)
        case report(StreakDetailReport)
    }

    public private(set) var displayedMonth: LocalDate
    public private(set) var selectedDay: LocalDate

    public let streak: StepStreakTracker
    @ObservationIgnored private let calendar: ActivityCalendar
    @ObservationIgnored private let formatter: ActivityFormatter
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(
        streak: StepStreakTracker,
        calendar: ActivityCalendar = ActivityCalendar(),
        formatter: ActivityFormatter = ActivityFormatter(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.streak = streak
        self.calendar = calendar
        self.formatter = formatter
        self.now = now
        let today = calendar.day(containing: now())
        displayedMonth = calendar.startOfMonth(containing: today)
        selectedDay = today
    }

    private var today: LocalDate { calendar.day(containing: now()) }

    public var content: Content {
        guard let history = streak.history.history else {
            switch streak.history.state {
            case .noReadAccess: return .noReadAccess
            case .failed(let message): return .failed(message)
            case .idle, .loading, .loaded: return .loading
            }
        }
        return .report(StreakDetailReport.make(
            history: history,
            goals: streak.goals.history,
            record: streak.record,
            today: today,
            displayedMonth: displayedMonth,
            selectedDay: selectedDay,
            calendar: calendar,
            formatter: formatter
        ))
    }

    public func load() async {
        await streak.loadIfNeeded()
    }

    /// Tag auswählen (Zukunft nicht).
    public func select(_ day: LocalDate) {
        guard day <= today else { return }
        selectedDay = day
    }

    public func showPreviousMonth() {
        guard case .report(let report) = content, report.canShowPreviousMonth else { return }
        displayedMonth = calendar.addingMonths(-1, to: displayedMonth)
        selectedDay = calendar.endOfMonth(containing: displayedMonth)
    }

    public func showNextMonth() {
        guard case .report(let report) = content, report.canShowNextMonth else { return }
        displayedMonth = calendar.addingMonths(1, to: displayedMonth)
        selectedDay = min(calendar.endOfMonth(containing: displayedMonth), today)
    }
}
