import Foundation
import PaceCore
import PaceTestSupport
import Testing

struct TodayStepsLoaderTests {
    private let now = Fixtures.date(2026, 10, 16, 14, 30)

    private func makeLoader(_ service: HealthServiceStub, now: Date? = nil) -> TodayStepsLoader {
        let currentDate = now ?? self.now
        return TodayStepsLoader(provider: service, calendar: Fixtures.calendar, now: { currentDate })
    }

    @Test func returnsStepsOfCurrentCalendarDay() async throws {
        let service = HealthServiceStub { $0.stepCount = .success(8_432) }

        let result = try await makeLoader(service).load()

        let expectedDay = Fixtures.date(2026, 10, 16)
        #expect(result == .available(DailyStepCount(day: expectedDay, steps: 8_432, updatedAt: now)))
        #expect(service.recordedCalls.stepCountIntervals == [
            DateInterval(start: expectedDay, end: Fixtures.date(2026, 10, 17)),
        ])
        #expect(service.recordedCalls.hasAnyStepSamplesQueries == 0)
    }

    @Test func dayIntervalRespectsDaylightSavingTimeChange() async throws {
        // In Berlin endet die Sommerzeit am 25.10.2026 – der Tag hat 25 Stunden.
        let service = HealthServiceStub { $0.stepCount = .success(100) }

        _ = try await makeLoader(service, now: Fixtures.date(2026, 10, 25, 20)).load()

        let interval = try #require(service.recordedCalls.stepCountIntervals.first)
        #expect(interval.start == Fixtures.date(2026, 10, 25))
        #expect(interval.duration == 25 * 60 * 60)
    }

    @Test func reportsZeroStepsWhenTodayIsEmptyButOtherStepDataIsReadable() async throws {
        let service = HealthServiceStub {
            $0.stepCount = .success(nil)
            $0.hasAnyStepSamples = .success(true)
        }

        let result = try await makeLoader(service).load()

        #expect(result == .available(DailyStepCount(day: Fixtures.date(2026, 10, 16), steps: 0, updatedAt: now)))
    }

    @Test func reportsMissingReadAccessWhenNoStepDataIsReadableAtAll() async throws {
        let service = HealthServiceStub {
            $0.stepCount = .success(nil)
            $0.hasAnyStepSamples = .success(false)
        }

        let result = try await makeLoader(service).load()

        #expect(result == .noReadAccess)
    }

    @Test func propagatesQueryErrors() async throws {
        let service = HealthServiceStub { $0.stepCount = .failure(.protectedDataUnavailable) }

        await #expect(throws: HealthDataError.protectedDataUnavailable) {
            try await makeLoader(service).load()
        }
    }
}
