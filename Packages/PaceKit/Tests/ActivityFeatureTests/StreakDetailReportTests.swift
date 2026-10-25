@testable import ActivityFeature
import Foundation
import PaceCore
import PaceTestSupport
import Testing

/// Flammen-Detailseite (Auftrag 4, §11): Serien, Rekord, Kalender, Tagesdetails – nur aus echten Tageswerten.
struct StreakDetailReportTests {
    private let calendar = Fixtures.activityCalendar
    private let formatter = ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: Fixtures.activityCalendar)
    private let goals = StepGoalHistory(changes: [.init(effectiveFrom: StepGoalHistory.origin, goal: 8_000)])
    /// Freitag, 16. Oktober 2026.
    private let today = Fixtures.day(2026, 10, 16)

    /// Verlauf ab 1. September: erreicht am 3.–6. Sept. (4 Tage), 20.–21. Sept. (2), 1. Okt. (1), 10.–15. Okt. (6);
    /// heute (16.) erst 3.000 Schritte; 8. Okt. ohne Daten.
    private func history() -> ActivityHistory {
        let first = Fixtures.day(2026, 9, 1)
        let reached: Set<LocalDate> = Set(
            [3, 4, 5, 6, 20, 21].map { Fixtures.day(2026, 9, $0) }
                + [1, 10, 11, 12, 13, 14, 15].map { Fixtures.day(2026, 10, $0) }
        )
        var days: [DailyActivitySummary] = []
        for day in calendar.days(from: first, through: today) where day != Fixtures.day(2026, 10, 8) {
            let steps = day == today ? 3_000 : reached.contains(day) ? 9_000 + day.day : 4_000
            days.append(DailyActivitySummary(date: day, healthSteps: steps, competitionSteps: steps))
        }
        return ActivityHistory(days: days, range: first...today, updatedAt: Date())
    }

    private func report(month: LocalDate? = nil, selected: LocalDate? = nil, record: StepStreakRecord? = nil) -> StreakDetailReport {
        PaceLocalization.$languageOverride.withValue(.german) {
            StreakDetailReport.make(
                history: history(),
                goals: goals,
                record: record,
                today: today,
                displayedMonth: month ?? Fixtures.day(2026, 10, 1),
                selectedDay: selected,
                calendar: calendar,
                formatter: formatter
            )
        }
    }

    @Test func currentStreakRecordStartAndLastSuccess() {
        let report = report()
        // 10.–15. Oktober; heute noch offen beendet die Serie nicht.
        #expect(report.currentDays == 6)
        #expect(!report.isTodayReached)
        #expect(report.currentStartText?.contains("10.") == true)
        #expect(report.lastReachedText?.contains("15.") == true)
        #expect(report.recordText == "6 Tage")
        #expect(report.statusText.contains("weiterbrennt"))
    }

    @Test func pastStreaksAreRealRunsNewestFirstFromTwoDays() {
        let runs = report().pastRuns
        // Laufende Serie (10.–15. Okt.) und Ein-Tages-Serie (1. Okt.) fehlen.
        #expect(runs.map(\.days) == [2, 4])
        #expect(runs.first?.start == Fixtures.day(2026, 9, 20))
        #expect(runs.last?.end == Fixtures.day(2026, 9, 6))
        #expect(runs.allSatisfy { !$0.isCurrent })
    }

    @Test func storedRecordOutsideTheLoadedHistoryIsKept() {
        let older = StepStreakRecord(days: 21, start: Fixtures.day(2026, 3, 1), end: Fixtures.day(2026, 3, 21))
        let report = report(record: older)
        #expect(report.recordText == "21 Tage")
        #expect(report.recordRangeText != nil)
        // Erfundene Serien gibt es nicht: Die früheren Serien bleiben die aus dem Verlauf.
        #expect(report.pastRuns.count == 2)
    }

    @Test func calendarMarksStartsEndsTodayFutureAndMissingData() throws {
        let cells = report().weeks.joined().compactMap { $0 }
        func cell(_ day: Int) throws -> StreakDetailReport.Cell {
            try #require(cells.first { $0.day == Fixtures.day(2026, 10, day) })
        }
        #expect(cells.count == 31)
        #expect(try cell(1).state == .reached)
        #expect(try cell(1).isRunStart && cell(1).isRunEnd)
        #expect(try cell(10).isRunStart)
        #expect(try !cell(12).isRunStart && !cell(12).isRunEnd)
        // Die laufende Serie endet nicht, nur weil heute das Ziel noch offen ist.
        #expect(try !cell(15).isRunEnd)
        #expect(try cell(16).state == .pending)
        #expect(try cell(16).isToday)
        #expect(try cell(17).state == .future)
        #expect(try !cell(17).isSelectable)
        #expect(try cell(8).state == .noData)
        #expect(try cell(2).state == .missed)
        // Wochen ab Montag: 1. Oktober 2026 ist ein Donnerstag.
        #expect(report().weeks[0].prefix(3).allSatisfy { $0 == nil })
        #expect(report().weekdays.count == 7)
    }

    @Test func selectedDayExplainsWhatHappened() throws {
        let continued = try #require(report(selected: Fixtures.day(2026, 10, 13)).selected)
        #expect(continued.statusText == "Flamme fortgesetzt – Tag 4 der Serie")
        #expect(continued.runLength == 4)
        #expect(continued.stepsText == "9.013 von 8.000 Schritten")
        #expect(continued.goalText == "Ziel an diesem Tag: 8.000 Schritte")

        let started = try #require(report(selected: Fixtures.day(2026, 10, 10)).selected)
        #expect(started.statusText == "Serie gestartet")

        let ended = try #require(report(month: Fixtures.day(2026, 9, 1), selected: Fixtures.day(2026, 9, 7)).selected)
        #expect(ended.statusText == "Tagesziel verpasst – die Flamme erlosch nach 4 Tagen")

        let open = try #require(report(selected: today).selected)
        #expect(open.statusText == "Heute noch 5.000 Schritte bis zum Ziel")

        let missing = try #require(report(selected: Fixtures.day(2026, 10, 8)).selected)
        #expect(missing.stepsText == nil)
        #expect(missing.statusText == "Für diesen Tag liegen keine Daten vor.")

        // Zukunft lässt sich nicht auswählen.
        #expect(report(selected: Fixtures.day(2026, 10, 20)).selected == nil)
    }

    @Test func monthNavigationStaysInsideTheHistory() {
        let october = report()
        #expect(october.canShowPreviousMonth)
        #expect(!october.canShowNextMonth)
        let september = report(month: Fixtures.day(2026, 9, 1))
        #expect(!september.canShowPreviousMonth)
        #expect(september.canShowNextMonth)
        #expect(september.historyNote.contains("1. September 2026"))
    }
}

/// Bestwerte rund um einen Tag (Kalender, Auftrag 4 §15).
struct PersonalBestsTests {
    private let calendar = Fixtures.activityCalendar
    private let formatter = ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: Fixtures.activityCalendar)
    private let today = Fixtures.day(2026, 10, 16)

    private func history() -> ActivityHistory {
        let first = Fixtures.day(2026, 9, 1)
        let steps: [LocalDate: Int] = [
            Fixtures.day(2026, 9, 18): 21_000,  // bester Tag im Verlauf (12 Monate)
            Fixtures.day(2026, 10, 3): 15_000,  // bester Tag im Oktober (Woche 28.9.–4.10.)
            Fixtures.day(2026, 10, 13): 12_480, // bester Tag dieser Woche (12.–18.10.)
            Fixtures.day(2026, 10, 14): 9_000,
        ]
        let days = calendar.days(from: first, through: today).map { day in
            DailyActivitySummary(date: day, healthSteps: steps[day] ?? 3_000, competitionSteps: steps[day] ?? 3_000)
        }
        return ActivityHistory(days: days, range: first...today, updatedAt: Date())
    }

    @Test func bestsRelativeToTheSelectedDay() throws {
        let record = StepStreakRecord(days: 9, start: Fixtures.day(2026, 9, 2), end: Fixtures.day(2026, 9, 10))
        let bests = PaceLocalization.$languageOverride.withValue(.german) {
            PersonalBests.around(Fixtures.day(2026, 10, 14), history: history(), today: today, record: record, calendar: calendar, formatter: formatter)
        }
        #expect(bests.map(\.kind) == [.dayOfWeek, .dayOfMonth, .dayOverall, .longestStreak])
        #expect(bests[0].title == "Bester Tag dieser Woche")
        #expect(bests[0].value == "12.480 Schritte")
        #expect(bests[1].title == "Bester Tag dieses Monats")
        #expect(bests[1].value == "15.000 Schritte")
        #expect(bests[2].value == "21.000 Schritte")
        #expect(bests[3].value == "9 Tage")
        #expect(bests.allSatisfy { !$0.isThisDay })
    }

    @Test func theBestDayItselfIsMarkedAndPastPeriodsAreNamed() {
        let bests = PaceLocalization.$languageOverride.withValue(.german) {
            PersonalBests.around(Fixtures.day(2026, 9, 18), history: history(), today: today, record: nil, calendar: calendar, formatter: formatter)
        }
        #expect(bests.map(\.kind) == [.dayOfWeek, .dayOfMonth, .dayOverall])
        #expect(bests[0].title == "Bester Tag der Woche")
        #expect(bests[1].title == "Bester Tag im September 2026")
        #expect(bests.allSatisfy { $0.isThisDay })
    }

    @Test func noStepsMeansNoBests() {
        let first = Fixtures.day(2026, 10, 1)
        let empty = ActivityHistory(
            days: calendar.days(from: first, through: today).map { DailyActivitySummary(date: $0, healthSteps: 0, competitionSteps: 0) },
            range: first...today, updatedAt: Date()
        )
        #expect(PersonalBests.around(today, history: empty, today: today, record: nil, calendar: calendar, formatter: formatter).isEmpty)
    }
}
