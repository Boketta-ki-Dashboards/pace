import ActivityFeature
import Foundation
import PaceCore
import PaceTestSupport
import Testing

/// Tagesdetails (Referenzbild 8): Werte, Rest bis zum Ziel, Streak bis gestern, letzte 7 Tage, optionale Herzwerte.
@MainActor
struct DayDetailsTests {
    private let calendar = Fixtures.activityCalendar
    /// Samstag, 17. Oktober 2026, 15:20.
    private let today = Fixtures.day(2026, 10, 17)
    private let now: @Sendable () -> Date = { Fixtures.date(2026, 10, 17, 15, 20) }
    private let german = ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: Fixtures.activityCalendar)

    /// Letzte 7 Tage wie in Bild 8 (So 11. bis Sa 17. Oktober), davor eine 12-Tage-Serie im September.
    private static let lastWeek = [4_100, 6_320, 7_231, 10_654, 11_203, 10_021, 8_432]

    private func summary(_ day: LocalDate, _ steps: Int, details: Bool = false) -> DailyActivitySummary {
        DailyActivitySummary(
            date: day,
            healthSteps: steps,
            competitionSteps: steps,
            walkingRunningDistanceMeters: details ? 6_100 : nil,
            activeEnergyKilocalories: details ? 324 : nil,
            flightsClimbed: details ? 8 : nil,
            exerciseMinutes: details ? 32 : nil
        )
    }

    private func history(todaySteps: Int = 8_432) -> ActivityHistory {
        let first = Fixtures.day(2026, 8, 20)
        var days = calendar.days(from: first, through: calendar.adding(-7, to: today)).map { day in
            // 1.–12. September: Ziel erreicht (Rekord 12 Tage), danach knapp verfehlt.
            summary(day, day.month == 9 && day.day <= 12 ? 12_000 : 9_000)
        }
        for (offset, steps) in Self.lastWeek.enumerated() {
            let day = calendar.adding(offset - 6, to: today)
            days.append(summary(day, day == today ? todaySteps : steps, details: day == today))
        }
        return ActivityHistory(days: days, range: first...today, updatedAt: now())
    }

    private func makeReport(
        day: LocalDate? = nil,
        history: ActivityHistory? = nil,
        hourly: [Int: Double]? = nil,
        heartRate: DailyHeartRate? = nil,
        formatter: ActivityFormatter? = nil
    ) -> DayDetailsReport {
        DayDetailsReport.make(DayDetailsReport.Input(
            day: day ?? today,
            today: today,
            history: history ?? self.history(),
            goals: StepGoalHistory(),
            record: StepStreakRecord(days: 12, start: Fixtures.day(2026, 9, 1), end: Fixtures.day(2026, 9, 12)),
            hourly: hourly,
            currentHour: 15,
            heartRate: heartRate,
            formatter: formatter ?? german,
            calendar: calendar
        ))
    }

    // MARK: Bericht

    @Test func todayMatchesTheReference() throws {
        let report = makeReport()

        #expect(report.dateText == "Samstag, 17. Oktober 2026")
        #expect(report.isToday)
        let progress = try #require(report.progress)
        #expect(progress.percentText(formatter: german) == "84%")
        #expect(progress.stepsText(formatter: german) == "8.432")
        #expect(progress.stepsUnit == "Schritte")
        #expect(progress.goalOnDayText(formatter: german) == "Tagesziel an diesem Tag: 10.000")
        #expect(progress.remainingText(formatter: german) == "Noch 1.568 Schritte")

        #expect(report.tiles.map(\.value) == ["6,1 km", "324 kcal", "8", "32"])
        #expect(report.tiles.map(\.title) == ["Distanz", "Aktiv", "Stockwerke", "Trainingsminuten"])
        #expect(report.tiles.allSatisfy { $0.isAvailable })
        #expect(report.heartTiles.isEmpty)
        #expect(report.notes.isEmpty)
    }

    @Test func streakCountsThroughYesterdayWhileTodayIsOpen() {
        let streak = makeReport().streak

        #expect(streak.valueText == "3 Tage")
        #expect(streak.caption == "Aktuelle Serie bis gestern")
        #expect(streak.hint == "Erreiche heute dein Ziel für Tag 4.")
        #expect(streak.recordText == "Rekord: 12 Tage")
        #expect(streak.isActive)
        #expect(!streak.isTodayReached)
    }

    @Test func reachedTodayCountsTheDay() {
        let streak = makeReport(history: history(todaySteps: 10_400)).streak

        #expect(streak.valueText == "4 Tage")
        #expect(streak.caption == "Aktuelle Serie inklusive heute")
        #expect(streak.hint == "Heute geschafft – Tag 4 zählt.")
        #expect(streak.isTodayReached)
    }

    @Test func noRunningStreakInvitesToStartOne() {
        var values = history()
        values = values.merging([summary(calendar.adding(-1, to: today), 2_000)])
        let streak = makeReport(history: values).streak

        #expect(streak.valueText == "0 Tage")
        #expect(streak.hint == "Erreiche heute dein Ziel, um eine neue Serie zu starten.")
        #expect(!streak.isActive)
    }

    @Test func pastDaysDescribeTheStreakOnThatDay() {
        let reached = makeReport(day: Fixtures.day(2026, 10, 15)).streak
        #expect(reached.valueText == "2 Tage")
        #expect(reached.caption == "Serie an diesem Tag")
        #expect(reached.hint == "Ziel erreicht – Tag 2 der Serie.")

        let ended = makeReport(day: Fixtures.day(2026, 9, 13)).streak
        #expect(ended.valueText == "12 Tage")
        #expect(ended.caption == "Serie bis zum Vortag")
        #expect(ended.hint == "Ziel nicht erreicht – die Serie endete an diesem Tag.")

        let none = makeReport(day: Fixtures.day(2026, 10, 12)).streak
        #expect(none.valueText == "0 Tage")
        #expect(none.hint == "Ziel nicht erreicht – an diesem Tag lief keine Serie.")
    }

    @Test func pastDayShowsWhatWasMissing() throws {
        let report = makeReport(day: Fixtures.day(2026, 10, 13))
        let progress = try #require(report.progress)
        #expect(progress.remainingText(formatter: german) == "2.769 Schritte haben gefehlt")
        #expect(report.dateText == "Dienstag, 13. Oktober 2026")
        #expect(!report.isToday)
    }

    @Test func lastSevenDaysEndWithTheShownDay() {
        let days = makeReport().recentDays

        #expect(days.map(\.weekday) == ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"])
        #expect(days.map(\.valueText) == ["4.100", "6.320", "7.231", "10.654", "11.203", "10.021", "84%"])
        #expect(days.map(\.status) == [
            .inProgress(fraction: 0.41), .inProgress(fraction: 0.632), .inProgress(fraction: 0.7231),
            .reached, .reached, .reached, .inProgress(fraction: 0.8432),
        ])
        #expect(days.last?.isSelected == true)
        #expect(days.first?.accessibilityLabel == "Sonntag, 11. Oktober: 4.100 Schritte, 41 % des Tagesziels")
    }

    @Test func dayWithoutDataShowsDashesAndNoChart() {
        let report = makeReport(day: Fixtures.day(2026, 8, 10))

        #expect(report.progress == nil)
        #expect(report.tiles.allSatisfy { !$0.isAvailable && $0.value == "–" })
        #expect(report.hourly == .unavailable)
        #expect(report.notes == ["Für diesen Tag liegen keine Daten vor."])
        #expect(report.recentDays.allSatisfy { $0.status == .noData && $0.valueText == "–" })
    }

    @Test func unreadableMetricsAreNotShownAsZero() {
        let report = makeReport(day: Fixtures.day(2026, 10, 16))
        #expect(report.tiles.map(\.value) == ["–", "–", "–", "–"])
        #expect(report.tiles.allSatisfy { !$0.isAvailable })
        #expect(report.tiles[0].accessibilityLabel == "Distanz: nicht verfügbar")
    }

    @Test func manualStepsAreNoted() {
        let manual = DailyActivitySummary(date: today, healthSteps: 9_000, competitionSteps: 8_432)
        let report = makeReport(history: history().merging([manual]))
        #expect(report.notes.first?.hasPrefix("In Apple Health: 9.000 Schritte.") == true)
    }

    // MARK: Stundenwerte

    @Test func hourlyBarsStopAtTheCurrentHourToday() throws {
        #expect(makeReport().hourly == .loading)

        let loaded = makeReport(hourly: [7: 640, 8: 1_210, 15: 300])
        guard case .loaded(let bars) = loaded.hourly else { throw UnexpectedStateError() }
        #expect(bars.count == 24)
        #expect(bars[7].value == 640)
        #expect(bars[9].value == 0)
        #expect(bars[15].isCurrent)
        #expect(bars[16].value == nil)

        let past = makeReport(day: Fixtures.day(2026, 10, 15), hourly: [22: 100])
        guard case .loaded(let pastBars) = past.hourly else { throw UnexpectedStateError() }
        #expect(pastBars[23].value == 0)
        #expect(!pastBars.contains { $0.isCurrent })
    }

    // MARK: Herzwerte

    @Test func heartRateTilesOnlyForAvailableValues() {
        let both = makeReport(heartRate: DailyHeartRate(restingBeatsPerMinute: 61.6, walkingAverageBeatsPerMinute: 98))
        #expect(both.heartTiles.map(\.value) == ["62", "98"])
        #expect(both.heartTiles.map(\.unit) == ["/min", "/min"])
        #expect(both.heartTiles.map(\.title) == ["Ruhepuls", "Ø Puls beim Gehen"])

        let resting = makeReport(heartRate: DailyHeartRate(restingBeatsPerMinute: 58, walkingAverageBeatsPerMinute: nil))
        #expect(resting.heartTiles.map(\.kind) == [.restingHeartRate])

        // Kein Wert wird als 0 gezeigt.
        let zero = makeReport(heartRate: DailyHeartRate(restingBeatsPerMinute: 0, walkingAverageBeatsPerMinute: nil))
        #expect(zero.heartTiles.isEmpty)
        #expect(makeReport(heartRate: .empty).heartTiles.isEmpty)
    }

    // MARK: Sprachen

    @Test func englishTexts() throws {
        let english = ActivityFormatter(locale: Locale(identifier: "en_US"), calendar: calendar)
        try PaceLocalization.$languageOverride.withValue(.english) {
            let report = makeReport(heartRate: DailyHeartRate(restingBeatsPerMinute: 62, walkingAverageBeatsPerMinute: nil), formatter: english)
            #expect(report.dateText == "Saturday, October 17, 2026")
            let progress = try #require(report.progress)
            #expect(progress.goalOnDayText(formatter: english) == "Goal on this day: 10,000")
            #expect(progress.remainingText(formatter: english) == "1,568 steps to go")
            #expect(report.streak.valueText == "3 days")
            #expect(report.streak.caption == "Current streak through yesterday")
            #expect(report.streak.hint == "Reach your goal today for day 4.")
            #expect(report.streak.recordText == "Record: 12 days")
            #expect(report.heartTiles.first?.unit == "bpm")
            #expect(report.recentDays.map(\.weekday) == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        }
    }

    @Test func russianTextsUseCorrectPlurals() throws {
        let russian = ActivityFormatter(locale: Locale(identifier: "ru_RU"), calendar: calendar)
        try PaceLocalization.$languageOverride.withValue(.russian) {
            let report = makeReport(formatter: russian)
            #expect(report.dateText.hasPrefix("Суббота, 17 октября 2026"))
            let progress = try #require(report.progress)
            #expect(progress.stepsUnit == "шага")
            #expect(progress.remainingText(formatter: russian) == "Ещё \(russian.steps(1_568)) шагов")
            #expect(report.streak.valueText == "3 дня")
            #expect(report.streak.recordText == "Рекорд: 12 дней")
            #expect(report.streak.hint == "Достигни цели сегодня – это будет день 4.")
            #expect(report.recentDays.last?.valueText == "84\u{00A0}%")

            let reached = self.makeReport(history: history(todaySteps: 10_400), formatter: russian).streak
            #expect(reached.valueText == "4 дня")
            let single = self.makeReport(day: Fixtures.day(2026, 10, 14), formatter: russian).streak
            #expect(single.valueText == "1 день")
        }
    }

    // MARK: ViewModel

    private final class LiveSource: ActivityOverviewSource {
        var detailsState: ActivityDetailsState = .loading
        func refresh() async {}
    }

    private func makeViewModel(day: LocalDate? = nil, health: HealthServiceStub) -> DayDetailsViewModel {
        let live = LiveSource()
        let store = ActivityHistoryStore(activityData: health, live: live, calendar: calendar, now: now)
        let streak = StepStreakTracker(
            history: store,
            goals: StepGoalSettings(store: InMemoryStepGoalStore(), calendar: calendar, now: now),
            recordStore: InMemoryStepStreakRecordStore(),
            calendar: calendar,
            now: now
        )
        return DayDetailsViewModel(
            day: day ?? today,
            origin: .statistics,
            streak: streak,
            activityData: health,
            live: live,
            calendar: calendar,
            formatter: german,
            now: now
        )
    }

    private func health(_ configure: (inout HealthServiceStub.Configuration) -> Void = { _ in }) -> HealthServiceStub {
        HealthServiceStub { configuration in
            for offset in -30 ... 0 {
                configuration.setSteps(9_000, on: calendar.adding(offset, to: today))
            }
            configuration.hourlyTotals[.competitionSteps] = [today: [8: 2_000, 12: 3_000]]
            configure(&configuration)
        }
    }

    @Test func viewModelLoadsHourlyValuesOncePerDay() async throws {
        let health = health()
        let viewModel = makeViewModel(health: health)
        await viewModel.loadIfNeeded()

        await viewModel.loadHourly()
        await viewModel.loadHourly()

        #expect(health.recordedCalls.hourlyTotalsRequests.count == 1)
        #expect(health.recordedCalls.hourlyTotalsRequests.first?.metric == .competitionSteps)
        guard case .report(let report) = viewModel.content, case .loaded(let bars) = report.hourly else {
            throw UnexpectedStateError()
        }
        #expect(bars[12].value == 3_000)
        #expect(viewModel.backTitle == "Statistik")
    }

    @Test func futureDaysAreClampedToToday() {
        let viewModel = makeViewModel(day: Fixtures.day(2026, 11, 2), health: health())
        #expect(viewModel.day == today)
    }

    @Test func withoutHeartRateSourceNothingIsOffered() async throws {
        let health = health()
        let viewModel = makeViewModel(health: health)

        await viewModel.loadIfNeeded()

        #expect(!viewModel.offersHeartRate)
        #expect(health.recordedCalls.dailyHeartRateRequests.isEmpty)
        guard case .report(let report) = viewModel.content else { throw UnexpectedStateError() }
        #expect(report.heartTiles.isEmpty)
    }

    @Test func heartRateIsRequestedOnlyOnDemand() async throws {
        let health = health { configuration in
            configuration.heartRateAccess = .notRequested
            configuration.heartRates[today] = DailyHeartRate(restingBeatsPerMinute: 62, walkingAverageBeatsPerMinute: 98)
        }
        let viewModel = makeViewModel(health: health)

        await viewModel.loadIfNeeded()
        #expect(viewModel.offersHeartRate)
        #expect(health.recordedCalls.heartRateAccessRequests == 0)
        #expect(health.recordedCalls.dailyHeartRateRequests.isEmpty)
        // Die Abfrage beim ersten Start bleibt unverändert.
        #expect(health.recordedCalls.authorizationRequests == 0)

        await viewModel.requestHeartRateAccess()

        #expect(health.recordedCalls.heartRateAccessRequests == 1)
        #expect(!viewModel.offersHeartRate)
        #expect(health.recordedCalls.dailyHeartRateRequests == [today])
        guard case .report(let report) = viewModel.content else { throw UnexpectedStateError() }
        #expect(report.heartTiles.map(\.value) == ["62", "98"])
        #expect(!viewModel.showsNoHeartRateNote)
    }

    @Test func grantedButEmptyHeartRateExplainsWhy() async {
        let health = health { $0.heartRateAccess = .notRequested }
        let viewModel = makeViewModel(health: health)
        await viewModel.loadIfNeeded()

        await viewModel.requestHeartRateAccess()

        #expect(viewModel.showsNoHeartRateNote)
    }

    @Test func failedHeartRateRequestKeepsTheOffer() async {
        let health = health { configuration in
            configuration.heartRateAccess = .notRequested
            configuration.requestHeartRateAccessResult = .failure(.authorizationRequestFailed(reason: "test"))
        }
        let viewModel = makeViewModel(health: health)
        await viewModel.loadIfNeeded()

        await viewModel.requestHeartRateAccess()

        #expect(viewModel.heartRateRequestFailed)
        #expect(viewModel.offersHeartRate)
        #expect(!viewModel.isRequestingHeartRate)
    }

    @Test func heartRateReadErrorsHideTheTiles() async throws {
        let health = health { configuration in
            configuration.heartRateAccess = .requested
            configuration.heartRateError = .queryFailed(reason: "test")
        }
        let viewModel = makeViewModel(health: health)

        await viewModel.loadIfNeeded()

        guard case .report(let report) = viewModel.content else { throw UnexpectedStateError() }
        #expect(report.heartTiles.isEmpty)
        #expect(!viewModel.offersHeartRate)
    }
}
