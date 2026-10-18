import ActivityFeature
import Foundation
import PaceCore
import PaceTestSupport
import Testing

/// Freitag, 16.10.2026. Aktuelle Woche: Mo 12. bis So 18. Oktober.
struct StatisticsReportTests {
    private let calendar = Fixtures.activityCalendar
    private let formatter = ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: Fixtures.activityCalendar)
    private let today = Fixtures.day(2026, 10, 16)

    private func day(_ offset: Int) -> LocalDate {
        calendar.adding(offset, to: today)
    }

    private func history(
        from first: LocalDate = Fixtures.day(2026, 9, 1),
        steps: [LocalDate: Int] = [:],
        defaultSteps: Int = 0,
        health: [LocalDate: Int] = [:],
        distancePerStep: Double? = nil,
        energyPerStep: Double? = nil,
        flights: Int? = nil,
        exercise: Int? = nil
    ) -> ActivityHistory {
        let days = calendar.days(from: first, through: today).map { date in
            let competition = steps[date] ?? defaultSteps
            return DailyActivitySummary(
                date: date,
                healthSteps: health[date] ?? competition,
                competitionSteps: competition,
                walkingRunningDistanceMeters: distancePerStep.map { Double(competition) * $0 },
                activeEnergyKilocalories: energyPerStep.map { Double(competition) * $0 },
                flightsClimbed: flights,
                exerciseMinutes: exercise
            )
        }
        return ActivityHistory(days: days, range: first...today, updatedAt: Fixtures.date(2026, 10, 16, 18))
    }

    private func report(
        _ period: StatisticsPeriod,
        _ metric: StatisticsMetric = .steps,
        anchor: LocalDate? = nil,
        history: ActivityHistory,
        goals: StepGoalHistory = StepGoalHistory(initialGoal: 10_000),
        record: StepStreakRecord? = nil,
        hourly: HourlyValues? = nil,
        currentHour: Int = 18,
        fraction: Double = 0
    ) -> StatisticsReport {
        StatisticsReport.make(StatisticsReport.Input(
            period: period,
            metric: metric,
            anchor: anchor ?? today,
            history: history,
            goals: goals,
            record: record,
            hourly: hourly,
            today: today,
            currentHour: currentHour,
            fractionOfCurrentHour: fraction,
            formatter: formatter,
            calendar: calendar
        ))
    }

    /// Mo 3.000, Di 12.000, Mi 5.000, Do 10.000, Fr (heute) 8.742; Vorwoche täglich 7.000.
    private var currentWeek: [LocalDate: Int] {
        var steps: [LocalDate: Int] = [day(-4): 3_000, day(-3): 12_000, day(-2): 5_000, day(-1): 10_000, day(0): 8_742]
        for offset in -11 ... -5 { steps[day(offset)] = 7_000 }
        return steps
    }

    // MARK: Tag

    @Test func todayShowsCompetitionStepsGoalAndAllMetrics() {
        let history = history(
            steps: [today: 8_742], health: [today: 9_120], distancePerStep: 0.732, energyPerStep: 0.04375, exercise: 34
        )

        let report = report(.day, history: history)

        #expect(report.title == "Heute")
        #expect(report.subtitle == "Freitag, 16. Oktober")
        #expect(report.valueText == "8.742")
        #expect(report.unitText == "Schritte")
        #expect(report.secondaryText == "von 10.000 Schritten · 87 %")
        #expect(report.goalReached == false)
        #expect(report.tiles.map(\.kind) == [.steps, .distance, .activeEnergy, .flights, .exercise, .goal, .progress])
        #expect(report.tiles.map(\.value) == [
            "8.742", "6,4 km", "382 kcal", StatisticsReport.unavailable, "34 Min.", "Noch 1.258", "87 %",
        ])
        // Nicht lesbare Kennzahlen sind „nicht verfügbar“, nie 0.
        #expect(report.tiles.filter { !$0.isAvailable }.map(\.kind) == [.flights])
        #expect(report.notes == ["In Apple Health: 9.120 Schritte. \(ActivityTexts.manualStepsNote)"])
        #expect(!report.canShowNext)
        #expect(report.canShowPrevious)
    }

    @Test func noManualNoteWhenStepsMatch() {
        let report = report(.day, history: history(steps: [today: 8_742]))

        #expect(report.notes.isEmpty)
        #expect(report.tiles.first { $0.kind == .distance }?.value == StatisticsReport.unavailable)
    }

    @Test func pastDaysShowGoalOutcomeAndCompareWithThePreviousDay() {
        let history = history(steps: [day(-1): 12_000, day(-2): 8_000])

        let yesterday = report(.day, anchor: day(-1), history: history)
        #expect(yesterday.title == "Gestern")
        #expect(yesterday.goalReached == true)
        #expect(yesterday.tiles.first { $0.kind == .goal }?.value == "Erreicht")
        #expect(yesterday.comparison == .init(direction: .up, text: "+50 % ggü. Vortag"))
        #expect(yesterday.canShowNext)

        let wednesday = report(.day, anchor: day(-2), history: history)
        #expect(wednesday.title == "Mittwoch")
        #expect(wednesday.tiles.first { $0.kind == .goal }?.value == "Nicht erreicht")
        #expect(wednesday.comparison == nil) // Vortag hatte 0 Schritte
    }

    @Test func unavailableMetricIsNotShownAsZero() {
        let report = report(.day, .distance, history: history(steps: [today: 5_000]))

        #expect(report.valueText == nil)
        #expect(!report.isMetricAvailable)
        #expect(report.notes.first?.contains("Distanz") == true)
    }

    @Test func daysOutsideTheHistoryHaveNoData() {
        let report = report(.day, anchor: Fixtures.day(2026, 8, 20), history: history())

        #expect(report.valueText == nil)
        #expect(report.tiles.allSatisfy { !$0.isAvailable })
        #expect(report.notes == ["Für diesen Tag liegen keine Daten vor."])
        #expect(!report.canShowPrevious)
    }

    @Test func hourlyBarsAndComparisonAtTheSameTimeYesterday() {
        let history = history(steps: [today: 3_000])
        let hourly = HourlyValues(
            day: today,
            metric: .steps,
            values: [7: 1_000, 8: 2_000],
            previousDay: [7: 500, 8: 500, 9: 2_000, 20: 9_999]
        )

        let report = report(.day, history: history, hourly: hourly, currentHour: 9, fraction: 0.5)

        #expect(report.bars.count == 24)
        #expect(report.bars[8].value == 2_000)
        #expect(report.bars[9].value == 0)
        #expect(report.bars[9].isCurrent)
        #expect(report.bars[10].value == nil) // Zukunft
        // Gestern bis 9:30 Uhr: 500 + 500 + die Hälfte von 2.000 = 2.000 → heute 3.000 = +50 %.
        #expect(report.comparison == .init(direction: .up, text: "+50 % ggü. gestern zur gleichen Zeit"))

        let otherMetric = HourlyValues(day: today, metric: .distance, values: [7: 1], previousDay: nil)
        #expect(self.report(.day, history: history, hourly: otherMetric).bars.isEmpty)
    }

    // MARK: Woche

    @Test func weekShowsTotalsAverageGoalDaysBestDayAndComparison() {
        let report = report(.week, history: history(steps: currentWeek))

        #expect(report.title == "Diese Woche")
        #expect(report.subtitle == formatter.dayRange(day(-4), day(2)))
        #expect(report.valueText == "38.742")
        // 38.742 / 5 begonnene Tage = 7.748,4
        #expect(report.secondaryText == "Ø 7.748 pro Tag")
        #expect(report.bars.map(\.label) == ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"])
        #expect(report.bars.map(\.value) == [3_000, 12_000, 5_000, 10_000, 8_742, nil, nil])
        #expect(report.bars.filter(\.reachedGoal).map(\.label) == ["Di", "Do"])
        #expect(report.bars.filter(\.isCurrent).map(\.day) == [today])
        #expect(report.goalLine == 10_000)
        #expect(report.averageLine == 7_748.4)

        let tiles = Dictionary(uniqueKeysWithValues: report.tiles.map { ($0.kind, $0) })
        #expect(tiles[.average]?.value == "7.748 Schritte")
        #expect(tiles[.goalDays]?.value == "2 von 4")
        #expect(tiles[.goalDays]?.detail == "heute läuft noch")
        #expect(tiles[.bestDay]?.value == "12.000 Schritte")
        #expect(tiles[.bestDay]?.detail == formatter.dayWithWeekdayShort(day(-3)))
        #expect(tiles[.previous]?.value == "49.000 Schritte")
        #expect(tiles[.previous]?.detail == "Ø 7.000 Schritte pro Tag")
        // 7.748,4 / 7.000 − 1 = +10,7 %
        #expect(report.comparison == .init(direction: .up, text: "+11 % ggü. Vorwoche (Ø pro Tag)"))
        #expect(!report.canShowNext)
        #expect(report.canShowPrevious)
    }

    @Test func goalDaysCountTodayOnceReached() {
        var steps = currentWeek
        steps[today] = 10_000

        let report = report(.week, history: history(steps: steps))

        #expect(report.tiles.first { $0.kind == .goalDays }?.value == "3 von 5")
        #expect(report.tiles.first { $0.kind == .goalDays }?.detail == nil)
    }

    @Test func goalDaysUseTheGoalOfEachDay() {
        // Ab Mittwoch gilt 5.000: Mittwoch (5.000) zählt, Montag (3.000 bei 10.000) nicht.
        var goals = StepGoalHistory(initialGoal: 10_000)
        goals.setGoal(5_000, from: day(-2))

        let report = report(.week, history: history(steps: currentWeek), goals: goals)

        #expect(report.bars.filter(\.reachedGoal).map(\.label) == ["Di", "Mi", "Do", "Fr"])
        #expect(report.goalLine == 5_000)
    }

    @Test func bestDayTodayIsLabelledToday() {
        var steps = currentWeek
        steps[today] = 20_000

        let report = report(.week, history: history(steps: steps))

        #expect(report.tiles.first { $0.kind == .bestDay }?.detail == "Heute")
    }

    @Test func weekWithoutStepsHasNoBestDayAndNoComparison() {
        let report = report(.week, history: history())

        #expect(report.valueText == "0")
        #expect(!report.tiles.contains { $0.kind == .bestDay })
        #expect(report.averageLine == nil)
        #expect(report.comparison == nil) // Vorwoche: Ø 0 → kein Vergleich
    }

    @Test func manualNoteAppearsForDifferenceOnEarlierDay() {
        let report = report(.week, history: history(steps: currentWeek, health: [day(-2): 5_500]))

        #expect(report.notes == [ActivityTexts.manualStepsNote])
    }

    @Test func pastWeekTitleAndNavigation() {
        let lastWeek = report(.week, anchor: day(-7), history: history(steps: currentWeek))
        #expect(lastWeek.title == "Letzte Woche")
        #expect(lastWeek.canShowNext)
        #expect(lastWeek.bars.allSatisfy { $0.value != nil })
        #expect(!lastWeek.tiles.contains { $0.kind == .goalDays && $0.detail != nil })

        let older = report(.week, anchor: day(-21), history: history(steps: currentWeek))
        #expect(older.title == formatter.dayRange(day(-25), day(-19)))
        #expect(older.subtitle == nil)
    }

    @Test func distanceWeekUsesKilometersWithoutGoal() {
        let report = report(.week, .distance, history: history(steps: currentWeek, distancePerStep: 1))

        #expect(report.valueText == "38,7")
        #expect(report.unitText == "km")
        #expect(report.secondaryText == "Ø 7,7 km pro Tag")
        #expect(report.bars[1].value == 12) // km
        #expect(report.goalLine == nil)
        #expect(!report.tiles.contains { $0.kind == .goalDays })
        #expect(report.tiles.first { $0.kind == .previous }?.value == "49,0 km")
    }

    // MARK: Monat

    @Test func currentMonthIsPartialAndComparedPerDay() {
        // September: 6.000 pro Tag, Oktober: 9.000 pro Tag.
        var steps: [LocalDate: Int] = [:]
        for date in calendar.days(from: Fixtures.day(2026, 9, 1), through: Fixtures.day(2026, 9, 30)) { steps[date] = 6_000 }
        for date in calendar.days(from: Fixtures.day(2026, 10, 1), through: today) { steps[date] = 9_000 }

        let report = report(.month, history: history(steps: steps))

        #expect(report.title == "Dieser Monat")
        #expect(report.subtitle == "Oktober 2026")
        #expect(report.bars.count == 31)
        #expect(report.bars.compactMap(\.value).count == 16)
        #expect(report.valueText == "144.000")
        #expect(report.comparison == .init(direction: .up, text: "+50 % ggü. Vormonat (Ø pro Tag)"))
        #expect(report.tiles.first { $0.kind == .goalDays }?.value == "0 von 15")
    }

    @Test func monthAtTheStartOfTheHistoryHasNoPreviousMonth() {
        let report = report(.month, anchor: Fixtures.day(2026, 9, 10), history: history(defaultSteps: 5_000))

        #expect(report.title == "September 2026")
        #expect(report.subtitle == nil)
        #expect(!report.canShowPrevious)
        #expect(report.canShowNext)
        #expect(report.comparison == nil)
        #expect(!report.tiles.contains { $0.kind == .previous })
    }

    // MARK: Bestwerte

    @Test func bestsCoverDayWeekMonthAndRecordWithinTheHistory() {
        var steps: [LocalDate: Int] = [:]
        // Montag, 31.8. liegt vor dem Verlaufsbeginn (1.9.) – die angeschnittene Woche zählt nicht.
        for date in calendar.days(from: Fixtures.day(2026, 9, 1), through: Fixtures.day(2026, 9, 6)) { steps[date] = 20_000 }
        for date in calendar.days(from: Fixtures.day(2026, 9, 7), through: Fixtures.day(2026, 9, 13)) { steps[date] = 10_000 }
        steps[Fixtures.day(2026, 10, 2)] = 25_000
        let record = StepStreakRecord(days: 12, start: Fixtures.day(2026, 3, 1), end: Fixtures.day(2026, 3, 12))

        let report = report(.week, history: history(steps: steps), record: record)

        #expect(report.bests.map(\.title) == ["Bester Tag", "Beste Woche", "Bester Monat", "Längste Serie"])
        #expect(report.bests[0].value == "25.000 Schritte")
        #expect(report.bests[1].value == "70.000 Schritte")
        #expect(report.bests[1].detail == formatter.dayRange(Fixtures.day(2026, 9, 7), Fixtures.day(2026, 9, 13)))
        #expect(report.bests[2].value == "190.000 Schritte")
        #expect(report.bests[2].detail == "September 2026")
        #expect(report.bests[3].value == "12 Tage")

        #expect(self.report(.day, history: history(steps: steps), record: record).bests.isEmpty)
        #expect(!self.report(.week, .distance, history: history(steps: steps, distancePerStep: 1), record: record)
            .bests.contains { $0.title == "Längste Serie" })
    }

    @Test func formatterProducesGermanRangesAndPercentages() {
        #expect(formatter.dayRange(day(-4), day(2)) == "12.–18. Okt.")
        #expect(formatter.monthYear(today) == "Oktober 2026")
        #expect(formatter.signedPercent(0.107) == "+11 %")
        #expect(formatter.signedPercent(-0.08) == "−8 %")
        #expect(formatter.signedPercent(0.001) == "±0 %")
        #expect(formatter.percent(0.8742) == "87 %")
    }
}
