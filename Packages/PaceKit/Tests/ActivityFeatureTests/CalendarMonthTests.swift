import ActivityFeature
import Foundation
import PaceCore
import PaceTestSupport
import Testing

/// Monatsraster (Referenzbild 9): Wochenbeginn je Sprache, Zellzustände, historische Ziele, Monatsgrenzen, Tageskarte.
struct CalendarMonthTests {
    private let calendar = Fixtures.activityCalendar
    /// Samstag, 17. Oktober 2026.
    private let today = Fixtures.day(2026, 10, 17)

    /// Werte wie in Bild 9.
    private static let october: [Int: Int] = [
        1: 8_240, 2: 10_520, 3: 12_110, 4: 6_430, 5: 10_080, 6: 9_240, 7: 11_360, 8: 7_810, 9: 10_450,
        10: 13_220, 11: 5_980, 12: 10_710, 13: 8_620, 14: 11_040, 15: 9_180, 16: 10_230, 17: 8_432,
    ]

    private func history(from first: LocalDate = Fixtures.day(2025, 10, 1), values: [Int: Int] = october) -> ActivityHistory {
        let days = calendar.days(from: first, through: today).map { day in
            let steps = day.month == 10 && day.year == 2026 ? values[day.day] ?? 0 : 6_000
            return DailyActivitySummary(date: day, healthSteps: steps, competitionSteps: steps)
        }
        return ActivityHistory(days: days, range: first...today, updatedAt: Fixtures.date(2026, 10, 17, 12))
    }

    private func month(
        _ month: LocalDate? = nil,
        selected: LocalDate? = nil,
        history: ActivityHistory? = nil,
        goals: StepGoalHistory = StepGoalHistory(),
        locale: String = "de_DE"
    ) -> CalendarMonth {
        CalendarMonth.make(CalendarMonth.Input(
            month: month ?? today,
            selected: selected ?? today,
            history: history ?? self.history(),
            goals: goals,
            today: today,
            firstMonth: Fixtures.day(2025, 10, 1),
            formatter: ActivityFormatter(locale: Locale(identifier: locale), calendar: calendar),
            calendar: calendar
        ))
    }

    // MARK: Raster und Wochenbeginn

    @Test func germanWeekStartsOnMonday() {
        let october = month()

        #expect(october.title == "Oktober 2026")
        #expect(october.weekdays.map(\.title) == ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"])
        #expect(october.weekdays.first?.accessibilityLabel == "Montag")
        // Der 1. Oktober 2026 ist ein Donnerstag: drei leere Felder davor, eines nach dem 31.
        #expect(october.cells.prefix(3).allSatisfy { $0 == nil })
        #expect(october.cells[3]?.date == Fixtures.day(2026, 10, 1))
        #expect(october.cells.count == 35)
        #expect(october.weeks.count == 5)
        #expect(october.weeks.allSatisfy { $0.count == 7 })
        #expect(october.cells.last ?? nil == nil)
        #expect(october.days.count == 31)
    }

    @Test func englishWeekStartsOnSunday() {
        let october = PaceLocalization.$languageOverride.withValue(.english) { month(locale: "en_US") }

        #expect(october.title == "October 2026")
        #expect(october.weekdays.map(\.title) == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        #expect(october.cells.prefix(4).allSatisfy { $0 == nil })
        #expect(october.cells[4]?.date == Fixtures.day(2026, 10, 1))
        #expect(october.cells.count == 35)
    }

    @Test func russianWeekStartsOnMondayWithCapitalizedNames() {
        let october = PaceLocalization.$languageOverride.withValue(.russian) { month(locale: "ru_RU") }

        #expect(october.title == "Октябрь 2026")
        #expect(october.weekdays.map(\.title) == ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"])
        #expect(october.cells[3]?.date == Fixtures.day(2026, 10, 1))
    }

    @Test func monthStartingOnMondayHasNoLeadingCells() {
        // Juni 2026 beginnt an einem Montag und hat 30 Tage.
        let june = month(Fixtures.day(2026, 6, 10), selected: Fixtures.day(2026, 6, 30))

        #expect(june.cells.first??.date == Fixtures.day(2026, 6, 1))
        #expect(june.cells.count == 35)
        #expect(june.days.count == 30)
    }

    // MARK: Zellzustände

    @Test func cellStatesFollowTheReference() throws {
        let october = month()
        let days = Dictionary(uniqueKeysWithValues: october.days.map { ($0.date.day, $0) })

        let first = try #require(days[1])
        #expect(first.status == .inProgress(fraction: 0.824))
        #expect(first.stepsText == "8.240")
        #expect(first.dayText == "1")

        let second = try #require(days[2])
        #expect(second.status == .reached)
        #expect(second.stepsText == "10.520")

        let todayCell = try #require(days[17])
        #expect(todayCell.isToday)
        #expect(todayCell.isSelected)
        #expect(todayCell.status == .inProgress(fraction: 0.8432))
        #expect(todayCell.stepsText == "8.432")

        let future = try #require(days[18])
        #expect(future.status == .future)
        #expect(future.stepsText == "–")
        #expect(future.progress == nil)
        #expect(!future.isSelectable)

        let reached = october.days.filter { $0.status == .reached }.map(\.date.day)
        #expect(reached == [2, 3, 5, 7, 9, 10, 12, 14, 16])
    }

    @Test func measuredZeroDiffersFromMissingData() throws {
        // Verlauf erst ab dem 10. Oktober geladen; am 12. gemessene 0 Schritte.
        var values = Self.october
        values[12] = 0
        let october = month(history: history(from: Fixtures.day(2026, 10, 10), values: values))
        let days = Dictionary(uniqueKeysWithValues: october.days.map { ($0.date.day, $0) })

        let missing = try #require(days[5])
        #expect(missing.status == .noData)
        #expect(missing.stepsText == "–")
        #expect(missing.accessibilityLabel.hasSuffix("keine Daten"))

        let zero = try #require(days[12])
        #expect(zero.status == .inProgress(fraction: 0))
        #expect(zero.stepsText == "0")
    }

    @Test func historicalGoalsAreNotChangedRetroactively() throws {
        // Bis 9. Oktober 10.000, ab dem 10. nur noch 6.000 Schritte.
        let goals = StepGoalHistory(changes: [
            .init(effectiveFrom: StepGoalHistory.origin, goal: 10_000),
            .init(effectiveFrom: Fixtures.day(2026, 10, 10), goal: 6_000),
        ])
        let october = month(goals: goals)
        let days = Dictionary(uniqueKeysWithValues: october.days.map { ($0.date.day, $0) })

        // 8. Oktober: 7.810 von damals 10.000 – nicht erreicht, auch wenn heute 6.000 gelten.
        let eighth = try #require(days[8])
        #expect(eighth.status == .inProgress(fraction: 0.781))
        // 11. Oktober: 5.980 von 6.000 – knapp verfehlt; 13. Oktober: 8.620 von 6.000 – erreicht.
        let eleventh = try #require(days[11])
        #expect(eleventh.status == .inProgress(fraction: 5_980.0 / 6_000.0))
        let thirteenth = try #require(days[13])
        #expect(thirteenth.status == .reached)
        #expect(thirteenth.progress?.goal == 6_000)
    }

    // MARK: Monatsgrenzen

    @Test func navigationStopsAtTheCurrentAndTheFirstMonth() {
        let current = month()
        #expect(current.canShowPrevious)
        #expect(!current.canShowNext)

        let first = month(Fixtures.day(2025, 10, 15), selected: Fixtures.day(2025, 10, 31))
        #expect(!first.canShowPrevious)
        #expect(first.canShowNext)
        #expect(first.days.allSatisfy { $0.status != .future })
    }

    // MARK: Karte des ausgewählten Tages

    @Test func selectedDayCardInGerman() throws {
        let card = try #require(month().selectedCard)

        #expect(card.title == "Samstag, 17. Oktober")
        #expect(card.stepsText == "8.432")
        #expect(card.stepsUnit == "Schritte")
        #expect(card.goalText == "Tagesziel 10.000")
        #expect(card.detailText == "Noch 1.568 Schritte")
        #expect(card.percentText == "84%")
        #expect(!card.isReached)
    }

    @Test func selectedDayCardInEnglishAndRussian() throws {
        let english = try PaceLocalization.$languageOverride.withValue(.english) {
            try #require(month(locale: "en_US").selectedCard)
        }
        #expect(english.title == "Saturday, October 17")
        #expect(english.stepsText == "8,432")
        #expect(english.goalText == "Daily goal 10,000")
        #expect(english.detailText == "1,568 steps to go")
        #expect(english.percentText == "84%")

        let russian = try PaceLocalization.$languageOverride.withValue(.russian) {
            try #require(month(locale: "ru_RU").selectedCard)
        }
        let formatter = ActivityFormatter(locale: Locale(identifier: "ru_RU"), calendar: calendar)
        #expect(russian.title == "Суббота, 17 октября")
        #expect(russian.stepsText == formatter.steps(8_432))
        #expect((russian.stepsText ?? "").unicodeScalars.contains { $0 == "\u{00A0}" || $0 == "\u{202F}" })
        #expect(russian.stepsUnit == "шага")
        #expect(russian.detailText == "Ещё \(formatter.steps(1_568)) шагов")
        #expect(russian.percentText == "84\u{00A0}%")
    }

    @Test func selectedPastDayShowsWhatWasMissing() throws {
        let card = try #require(month(selected: Fixtures.day(2026, 10, 15)).selectedCard)
        #expect(card.detailText == "820 Schritte haben gefehlt")

        let reached = try #require(month(selected: Fixtures.day(2026, 10, 16)).selectedCard)
        #expect(reached.detailText == "Ziel erreicht")
        #expect(reached.isReached)
    }

    @Test func selectedDayWithoutDataSaysSo() throws {
        let october = month(selected: Fixtures.day(2026, 10, 5), history: history(from: Fixtures.day(2026, 10, 10)))
        let card = try #require(october.selectedCard)
        #expect(card.stepsText == nil)
        #expect(card.detailText == "Für diesen Tag liegen keine Daten vor.")
    }
}
