import Foundation
import PaceCore
import PaceTestSupport
import Testing

struct ActivitySummaryLoaderTests {
    private let now = Fixtures.date(2026, 10, 16, 14, 30)
    private let today = Fixtures.day(2026, 10, 16)

    private func makeLoader(_ service: HealthServiceStub, now: Date? = nil) -> ActivitySummaryLoader {
        let currentDate = now ?? self.now
        return ActivitySummaryLoader(provider: service, calendar: Fixtures.activityCalendar, now: { currentDate })
    }

    private func overview(_ result: ActivityLoadResult) throws -> ActivityOverview {
        guard case .available(let overview) = result else {
            Issue.record("Expected available overview, got \(result)")
            throw UnexpectedStateError()
        }
        return overview
    }

    // MARK: Aus Milestone 1 übernommene Szenarien

    @Test func returnsStepsOfCurrentCalendarDay() async throws {
        let service = HealthServiceStub { $0.setSteps(8_432, on: today) }

        let overview = try overview(try await makeLoader(service).load())

        #expect(overview.today.date == today)
        #expect(overview.today.healthSteps == 8_432)
        #expect(overview.today.competitionSteps == 8_432)
        #expect(overview.updatedAt == now)
    }

    @Test func requestsLastSevenLocalDaysForEveryMetric() async throws {
        let service = HealthServiceStub { $0.setSteps(1, on: today) }

        _ = try await makeLoader(service).load()

        let requests = service.recordedCalls.dailyTotalsRequests
        #expect(Set(requests.map(\.metric)) == Set(ActivityMetric.allCases))
        #expect(requests.allSatisfy { $0.days == Fixtures.day(2026, 10, 10)...today })
    }

    @Test func dayBoundariesRespectDaylightSavingTimeChange() async throws {
        // In Berlin endet die Sommerzeit am 25.10.2026 – „heute“ ist trotzdem genau dieser Kalendertag.
        let dstDay = Fixtures.day(2026, 10, 25)
        let service = HealthServiceStub { $0.setSteps(100, on: dstDay) }

        let overview = try overview(try await makeLoader(service, now: Fixtures.date(2026, 10, 25, 23, 30)).load())

        #expect(overview.today.date == dstDay)
        #expect(overview.today.healthSteps == 100)
        #expect(Fixtures.activityCalendar.interval(for: overview.today.date).duration == 25 * 60 * 60)
    }

    @Test func reportsZeroStepsWhenTodayIsEmptyButOtherStepDataIsReadable() async throws {
        let service = HealthServiceStub { $0.metricsWithAnySamples = [.steps] }

        let overview = try overview(try await makeLoader(service).load())

        #expect(overview.today.healthSteps == 0)
        #expect(overview.today.competitionSteps == 0)
    }

    @Test func reportsMissingReadAccessWhenNoStepDataIsReadableAtAll() async throws {
        let service = HealthServiceStub()

        let result = try await makeLoader(service).load()

        #expect(result == .noReadAccess)
    }

    @Test func propagatesQueryErrors() async throws {
        let service = HealthServiceStub { $0.dailyTotalsError = .protectedDataUnavailable }

        await #expect(throws: HealthDataError.protectedDataUnavailable) {
            try await makeLoader(service).load()
        }
    }

    // MARK: Competition Steps

    @Test func keepsHealthAndCompetitionStepsSeparate() async throws {
        let service = HealthServiceStub { $0.setSteps(9_000, competition: 7_500, on: today) }

        let overview = try overview(try await makeLoader(service).load())

        #expect(overview.today.healthSteps == 9_000)
        #expect(overview.today.competitionSteps == 7_500)
        #expect(overview.today.hasNonCompetitionSteps)
    }

    @Test func onlyManualStepsTodayMeansZeroCompetitionSteps() async throws {
        let service = HealthServiceStub {
            $0.set(.steps, 2_000, on: today)
            $0.metricsWithAnySamples.insert(.competitionSteps)
        }

        let overview = try overview(try await makeLoader(service).load())

        #expect(overview.today.healthSteps == 2_000)
        #expect(overview.today.competitionSteps == 0)
    }

    @Test func roundsFractionalStepSums() async throws {
        let service = HealthServiceStub {
            $0.set(.steps, 1_234.6, on: today)
            $0.set(.competitionSteps, 1_234.4, on: today)
        }

        let overview = try overview(try await makeLoader(service).load())

        #expect(overview.today.healthSteps == 1_235)
        #expect(overview.today.competitionSteps == 1_234)
    }

    // MARK: Optionale Kennzahlen

    @Test func unavailableMetricsAreNilNotZero() async throws {
        let service = HealthServiceStub { $0.setSteps(500, on: today) }

        let overview = try overview(try await makeLoader(service).load())

        #expect(overview.today.walkingRunningDistanceMeters == nil)
        #expect(overview.today.activeEnergyKilocalories == nil)
        #expect(overview.today.flightsClimbed == nil)
        #expect(overview.today.exerciseMinutes == nil)
        #expect(Set(service.recordedCalls.hasAnySamplesQueries) == [.walkingRunningDistance, .activeEnergy, .flightsClimbed, .exerciseTime])
    }

    @Test func availableMetricsAreZeroOnDaysWithoutSamples() async throws {
        let yesterday = Fixtures.day(2026, 10, 15)
        let service = HealthServiceStub {
            $0.setSteps(500, on: today)
            $0.set(.walkingRunningDistance, 4_200.5, on: today)
            $0.set(.activeEnergy, 310.2, on: yesterday)
            $0.set(.flightsClimbed, 7, on: today)
            $0.metricsWithAnySamples.insert(.exerciseTime)
        }

        let overview = try overview(try await makeLoader(service).load())

        #expect(overview.today.walkingRunningDistanceMeters == 4_200.5)
        #expect(overview.today.activeEnergyKilocalories == 0)
        #expect(overview.yesterday.activeEnergyKilocalories == 310.2)
        #expect(overview.yesterday.walkingRunningDistanceMeters == 0)
        #expect(overview.today.flightsClimbed == 7)
        #expect(overview.today.exerciseMinutes == 0)
    }

    // MARK: Zeiträume

    @Test func buildsAllPeriodsFromOneLoad() async throws {
        let service = HealthServiceStub {
            for (offset, steps) in [1_000, 2_000, 3_000, 4_000, 5_000, 6_000, 7_000].enumerated() {
                $0.setSteps(steps, on: Fixtures.activityCalendar.adding(offset - 6, to: today))
            }
        }

        let overview = try overview(try await makeLoader(service).load())

        // 10.10. (Sa) … 16.10. (Fr); die ISO-Woche beginnt am Montag, 12.10.
        #expect(overview.lastSevenDays.days.count == 7)
        #expect(overview.lastSevenDays.totalCompetitionSteps == 28_000)
        #expect(overview.currentWeek.days.map(\.date) == Fixtures.activityCalendar.days(from: Fixtures.day(2026, 10, 12), through: today))
        #expect(overview.currentWeek.totalCompetitionSteps == 25_000)
        #expect(overview.yesterday.competitionSteps == 6_000)
        #expect(overview.summary(for: Fixtures.day(2026, 10, 10))?.competitionSteps == 1_000)
        #expect(overview.summary(for: Fixtures.day(2026, 10, 9)) == nil)
        #expect(overview.summary(for: .today).days == [overview.today])
    }

    @Test func ignoresSamplesOutsideTheSevenDayWindow() async throws {
        let service = HealthServiceStub {
            $0.setSteps(99_999, on: Fixtures.day(2026, 10, 9))
            $0.setSteps(10, on: today)
        }

        let overview = try overview(try await makeLoader(service).load())

        #expect(overview.lastSevenDays.totalHealthSteps == 10)
    }
}
