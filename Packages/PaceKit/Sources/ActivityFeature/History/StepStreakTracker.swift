import Foundation
import Observation
import PaceCore

/// Persönliche Streak aus dem Bewegungsverlauf und dem Zielverlauf, live für Home, Statistiken und Profil.
@MainActor
@Observable
public final class StepStreakTracker {
    public let history: ActivityHistoryStore
    public let goals: StepGoalSettings

    private var storedRecord: StepStreakRecord?

    @ObservationIgnored private let recordStore: any StepStreakRecordStoring
    @ObservationIgnored private let calendar: ActivityCalendar
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(
        history: ActivityHistoryStore,
        goals: StepGoalSettings,
        recordStore: any StepStreakRecordStoring,
        calendar: ActivityCalendar = ActivityCalendar(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.history = history
        self.goals = goals
        self.recordStore = recordStore
        self.calendar = calendar
        self.now = now
        storedRecord = recordStore.load()
    }

    /// Aktuelle und längste Serie; `nil`, solange der Verlauf nicht geladen ist.
    public var streak: StepStreak? {
        guard let history = history.history else { return nil }
        return StepStreakCalculator.streak(history: history, goals: goals.history, today: today, calendar: calendar)
    }

    /// Rekord: der längere von gespeichertem Rekord und längster Serie im Verlauf.
    public var record: StepStreakRecord? {
        guard let streak else { return storedRecord }
        return StepStreakRecord.best(stored: storedRecord, streak: streak)
    }

    /// Status der letzten `count` Tage bis heute (für die Übersicht der erreichten Tage).
    public func recentDays(_ count: Int) -> [(day: LocalDate, status: StepStreakDayStatus)] {
        guard let history = history.history, count > 0 else { return [] }
        let today = today
        return StepStreakCalculator.dayStatuses(
            history: history,
            goals: goals.history,
            from: calendar.adding(-(count - 1), to: today),
            through: today,
            today: today,
            calendar: calendar
        )
    }

    /// Lädt den Verlauf bei Bedarf und speichert einen neuen Rekord.
    public func loadIfNeeded() async {
        await history.loadIfNeeded()
        saveRecordIfNeeded()
    }

    /// Speichert den Rekord, wenn die längste Serie den gespeicherten übertrifft.
    public func saveRecordIfNeeded() {
        guard let record, record != storedRecord else { return }
        storedRecord = record
        recordStore.save(record)
    }

    private var today: LocalDate {
        calendar.day(containing: now())
    }
}
