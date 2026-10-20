@testable import ActivityFeature
import DesignSystem
import Foundation
@testable import HomeFeature
@testable import LeaderboardFeature
import PaceCore
import PaceTestSupport
import SwiftUI
import Testing

/// Kalender (Bild 9), Tagesdetails (Bild 8), Statistiken und Rankings – jeweils mit Kopfzeile, Hell und Dunkel.
@MainActor
@Suite(.snapshotsEnabled)
struct ActivitySnapshotTests {
    private static let languages: [AppLanguage] = [.german, .english, .russian]

    private func page(_ content: some View) -> some View {
        content
            .padding(.horizontal, PaceSpacing.m)
            .padding(.vertical, PaceSpacing.m)
    }

    // MARK: Kalender und Tagesdetails

    @Test func calendar() async throws {
        let environment = await ActivitySnapshotEnvironment.make(october: ActivitySnapshotEnvironment.calendarOctober)
        let viewModel = CalendarViewModel(
            streak: environment.streak,
            activityData: environment.health,
            live: environment.live,
            calendar: environment.calendar,
            formatter: ActivityFormatter(calendar: environment.calendar),
            now: environment.now
        )
        await viewModel.loadIfNeeded()
        try Snapshot.render(page(CalendarSnapshotHost(viewModel: viewModel)), name: "calendar", languages: Self.languages)

        viewModel.showPrevious()
        try Snapshot.render(page(CalendarSnapshotHost(viewModel: viewModel)), name: "calendar-september")
    }

    @Test func dayDetails() async throws {
        let environment = await ActivitySnapshotEnvironment.make(
            october: ActivitySnapshotEnvironment.dayDetailsOctober,
            heartRateAccess: .requested
        )
        let viewModel = environment.dayDetails()
        await viewModel.loadIfNeeded()
        await viewModel.loadHourly()
        try Snapshot.render(page(DayDetailsSnapshotHost(viewModel: viewModel)), name: "day-details", languages: Self.languages)

        let withoutHeartRate = await ActivitySnapshotEnvironment.make(
            october: ActivitySnapshotEnvironment.dayDetailsOctober,
            heartRateAccess: .notRequested
        )
        let offer = withoutHeartRate.dayDetails()
        await offer.loadIfNeeded()
        await offer.loadHourly()
        try Snapshot.render(page(DayDetailsSnapshotHost(viewModel: offer)), name: "day-details-no-heart-rate")

        let past = environment.dayDetails(day: Fixtures.day(2026, 10, 13))
        await past.loadIfNeeded()
        await past.loadHourly()
        try Snapshot.render(page(DayDetailsSnapshotHost(viewModel: past)), name: "day-details-past")
    }

    // MARK: Statistiken

    @Test func statistics() async throws {
        let environment = await ActivitySnapshotEnvironment.make(october: ActivitySnapshotEnvironment.dayDetailsOctober)
        let routes: [(StatisticsRoute, String, [AppLanguage])] = [
            (StatisticsRoute(period: .day, metric: .steps), "statistics-day", Self.languages),
            (StatisticsRoute(period: .week, metric: .steps), "statistics-week", Self.languages),
            (StatisticsRoute(period: .month, metric: .distance), "statistics-month-distance", [.german]),
        ]
        for (route, name, languages) in routes {
            let statistics = StatisticsViewModel(
                route: route,
                streak: environment.streak,
                activityData: environment.health,
                live: environment.live,
                calendar: environment.calendar,
                formatter: ActivityFormatter(calendar: environment.calendar),
                now: environment.now
            )
            await statistics.loadIfNeeded()
            await statistics.loadHourly()
            try Snapshot.render(page(StatisticsSnapshotHost(viewModel: statistics)), name: name, languages: languages)
        }
    }

    // MARK: Rankings

    @Test func rankings() async throws {
        let (_, store) = try await SnapshotFixtures.makeDashboard()
        let leaderboard = LeaderboardViewModel(
            store: store,
            leaderboards: SnapshotFixtures.leaderboards(),
            syncing: nil,
            calendar: Fixtures.activityCalendar,
            now: { Fixtures.date(2026, 10, 16, 12) },
            topLimit: 8,
            social: SnapshotFixtures.socialRepository()
        )
        await leaderboard.loadIfNeeded()
        try Snapshot.render(page(LeaderboardContent(viewModel: leaderboard)), name: "rankings", languages: Self.languages)

        await leaderboard.selectFriends()
        try Snapshot.render(page(LeaderboardContent(viewModel: leaderboard)), name: "rankings-friends")

        await leaderboard.selectGroups()
        try Snapshot.render(page(LeaderboardContent(viewModel: leaderboard)), name: "rankings-groups")
    }

    @Test func rankingsOff() async throws {
        let profile = Fixtures.profile(displayName: "Niklas", regionalLeaderboardEnabled: false)
        let profiles = ProfileRepositoryStub { $0.profiles[profile.id] = profile }
        let store = ProfileStore(profile: profile, profiles: profiles, regions: RegionRepositoryStub(), cache: InMemoryProfileCache())
        try await store.loadHierarchyIfNeeded()
        let leaderboard = LeaderboardViewModel(
            store: store,
            leaderboards: SnapshotFixtures.leaderboards(),
            syncing: nil,
            calendar: Fixtures.activityCalendar,
            now: { Fixtures.date(2026, 10, 16, 12) },
            social: SnapshotFixtures.socialRepository()
        )
        await leaderboard.loadIfNeeded()
        #expect(leaderboard.isRankingHidden)
        try Snapshot.render(page(LeaderboardContent(viewModel: leaderboard)), name: "rankings-off", languages: Self.languages)
    }
}

// MARK: - Hosts

/// Berechnet den Inhalt beim Zeichnen – dadurch gelten Sprache und Formate des jeweiligen Snapshot-Durchlaufs.
private struct CalendarSnapshotHost: View {
    let viewModel: CalendarViewModel

    var body: some View {
        CalendarContent(
            content: viewModel.content,
            monthTitle: viewModel.monthTitle,
            canShowPrevious: viewModel.canShowPrevious,
            canShowNext: viewModel.canShowNext,
            onPrevious: {},
            onNext: {},
            onSelect: { _ in },
            onOpenDetails: { _ in },
            onRetry: {}
        )
    }
}

private struct DayDetailsSnapshotHost: View {
    let viewModel: DayDetailsViewModel

    var body: some View {
        DayDetailsContent(
            backTitle: viewModel.backTitle,
            content: viewModel.content,
            heartRate: DayDetailsContent.HeartRateOffer(isOffered: viewModel.offersHeartRate)
        )
    }
}

private struct StatisticsSnapshotHost: View {
    let viewModel: StatisticsViewModel

    var body: some View {
        StatisticsContent(
            report: report,
            hourly: viewModel.hourly,
            backTitle: PaceLocalization.text(de: "Home", en: "Home", ru: "Главная"),
            onSelectPeriod: { _ in },
            onSelectMetric: { _ in },
            onPrevious: {},
            onNext: {},
            onSelectDay: { _ in },
            onOpenDayDetails: { _ in }
        )
    }

    private var report: StatisticsReport? {
        guard case .report(let report) = viewModel.content else { return nil }
        return report
    }
}

// MARK: - Beispieldaten

/// Beispieldaten wie in den Referenzbildern 8 und 9 (nur für Bilder, nie in der App).
@MainActor
private struct ActivitySnapshotEnvironment {
    let health: HealthServiceStub
    let live: HomeViewModel
    let streak: StepStreakTracker
    let calendar: ActivityCalendar
    let now: @Sendable () -> Date

    /// Oktober wie im Kalender von Bild 9 (heute ist Samstag, der 17.).
    static let calendarOctober: [Int: Int] = [
        1: 8_240, 2: 10_520, 3: 12_110, 4: 6_430, 5: 10_080, 6: 9_240, 7: 11_360, 8: 7_810, 9: 10_450,
        10: 13_220, 11: 5_980, 12: 10_710, 13: 8_620, 14: 11_040, 15: 9_180, 16: 10_230, 17: 8_432,
    ]

    /// Wie Bild 8: die letzten 7 Tage So–Sa und eine Serie von 3 Tagen bis gestern.
    static let dayDetailsOctober: [Int: Int] = calendarOctober.merging(
        [11: 4_100, 12: 6_320, 13: 7_231, 14: 10_654, 15: 11_203, 16: 10_021, 17: 8_432]
    ) { _, new in new }

    static func make(october: [Int: Int], heartRateAccess: HeartRateAccess = .unavailable) async -> ActivitySnapshotEnvironment {
        let calendar = Fixtures.activityCalendar
        let today = Fixtures.day(2026, 10, 17)
        let health = HealthServiceStub { configuration in
            // Zwölf Monate Verlauf; im September eine Serie von 12 Tagen (Rekord).
            for offset in -380 ... -1 {
                let day = calendar.adding(offset, to: today)
                guard !(day.year == 2026 && day.month == 10) else { continue }
                let steps = day.year == 2026 && day.month == 9 && day.day <= 12
                    ? 12_000 + day.day * 37
                    : 5_200 + Int((offset * 7_919).magnitude % 4_600)
                configuration.setSteps(steps, on: day)
                configuration.set(.walkingRunningDistance, Double(steps) * 0.72, on: day)
                configuration.set(.activeEnergy, Double(steps) * 0.0384, on: day)
            }
            for (dayOfMonth, steps) in october {
                let day = Fixtures.day(2026, 10, dayOfMonth)
                configuration.setSteps(steps, on: day)
                configuration.set(.walkingRunningDistance, Double(steps) * 0.7234, on: day)
                configuration.set(.activeEnergy, Double(steps) * 0.03843, on: day)
            }
            configuration.set(.flightsClimbed, 8, on: today)
            configuration.set(.exerciseTime, 32, on: today)
            configuration.hourlyTotals[.competitionSteps] = [
                today: [
                    5: 40, 6: 110, 7: 180, 8: 280, 9: 900, 10: 760, 11: 330, 12: 1_180, 13: 1_020, 14: 600,
                    15: 30, 16: 90, 17: 560, 18: 1_180, 19: 700, 20: 292, 21: 120, 22: 60,
                ],
                Fixtures.day(2026, 10, 13): [7: 420, 8: 900, 12: 1_400, 13: 600, 17: 1_900, 18: 1_311, 19: 700],
            ]
            configuration.heartRateAccess = heartRateAccess
            configuration.heartRates[today] = DailyHeartRate(restingBeatsPerMinute: 62, walkingAverageBeatsPerMinute: 98)
        }
        // Spätabends, damit der Tagesverlauf wie in Bild 8 vollständig ist.
        let now: @Sendable () -> Date = { Fixtures.date(2026, 10, 17, 22, 40) }
        let live = HomeViewModel(activityData: health, calendar: calendar, now: now)
        await live.loadIfNeeded()
        let streak = StepStreakTracker(
            history: ActivityHistoryStore(activityData: health, live: live, calendar: calendar, now: now),
            goals: StepGoalSettings(store: InMemoryStepGoalStore(), calendar: calendar, now: now),
            recordStore: InMemoryStepStreakRecordStore(),
            calendar: calendar,
            now: now
        )
        await streak.loadIfNeeded()
        return ActivitySnapshotEnvironment(health: health, live: live, streak: streak, calendar: calendar, now: now)
    }

    func dayDetails(day: LocalDate = Fixtures.day(2026, 10, 17)) -> DayDetailsViewModel {
        DayDetailsViewModel(
            day: day,
            origin: .calendar,
            streak: streak,
            activityData: health,
            live: live,
            calendar: calendar,
            formatter: ActivityFormatter(calendar: calendar),
            now: now
        )
    }
}
