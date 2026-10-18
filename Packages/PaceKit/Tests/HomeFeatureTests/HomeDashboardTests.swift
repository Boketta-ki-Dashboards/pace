import ActivityFeature
import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
import Testing

// MARK: - Einstellungen

@MainActor
struct HomeSettingsTests {
    @Test func defaultsShowAllSections() {
        let settings = HomeSettings(store: InMemoryHomePreferencesStore())

        #expect(settings.visibleSections == [.regionRanks, .stepsToday, .week, .neighborhood, .friends, .groups])
    }

    @Test func legacyStepGoalIsDecodedForTheGoalHistory() throws {
        let json = #"{"stepGoal": 12500, "sections": [{"section": "week", "isVisible": true}]}"#
        let preferences = try JSONDecoder().decode(HomePreferences.self, from: Data(json.utf8))

        #expect(preferences.legacyStepGoal == 12_500)
        #expect(preferences.normalized().legacyStepGoal == 12_500)
    }

    @Test func sectionsCanBeHiddenButStepsTodayStaysVisible() {
        let store = InMemoryHomePreferencesStore()
        let settings = HomeSettings(store: store)

        settings.setVisible(false, for: .friends)
        settings.setVisible(false, for: .stepsToday)

        #expect(!settings.visibleSections.contains(.friends))
        #expect(settings.visibleSections.contains(.stepsToday))
        #expect(HomeSettings(store: store).visibleSections == settings.visibleSections)
    }

    @Test func sectionsCanBeReorderedAndReset() {
        let settings = HomeSettings(store: InMemoryHomePreferencesStore())

        // „Deine Schritte heute“ nach oben.
        settings.moveSections(fromOffsets: [1], toOffset: 0)
        #expect(settings.visibleSections.prefix(2) == [.stepsToday, .regionRanks])

        // „Deine Gruppen“ vor „Deine Woche“.
        settings.moveSections(fromOffsets: [5], toOffset: 2)
        #expect(settings.visibleSections == [.stepsToday, .regionRanks, .groups, .week, .neighborhood, .friends])

        settings.resetLayout()
        #expect(settings.visibleSections == HomeSection.allCases)
    }

    @Test func storedPreferencesAreRepaired() {
        let broken = HomePreferences(sections: [
            HomeSectionSetting(section: .week, isVisible: true),
            HomeSectionSetting(section: .week, isVisible: false),
            HomeSectionSetting(section: .stepsToday, isVisible: false),
        ])
        let settings = HomeSettings(store: InMemoryHomePreferencesStore(broken))

        #expect(settings.sections.map(\.section) == [.week, .stepsToday, .regionRanks, .neighborhood, .friends, .groups])
        #expect(settings.visibleSections.contains(.stepsToday))
    }
}

// MARK: - Schrittkarte & Woche

struct StepsTodaySummaryTests {
    private let formatter = ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: Fixtures.activityCalendar)
    private let today = Fixtures.day(2026, 10, 16)

    @Test func showsProgressTowardsGoal() {
        let day = DailyActivitySummary(
            date: today, healthSteps: 8_432, competitionSteps: 8_432,
            walkingRunningDistanceMeters: 6_100, activeEnergyKilocalories: 324
        )

        let summary = StepsTodaySummary(today: day, goal: 10_000, formatter: formatter)

        #expect(summary.stepsText == "8.432")
        #expect(summary.goalText == "von 10.000 Schritten")
        #expect(summary.percentText == "84%")
        #expect(summary.remainingText == "Noch 1.568 bis zu deinem Ziel")
        #expect(summary.distanceText == "6,1 km")
        #expect(summary.energyText == "324 kcal")
        #expect(summary.manualStepsNote == nil)
        #expect(!summary.isGoalReached)
    }

    @Test func goalReachedAndMissingMetricsStayHidden() {
        let day = DailyActivitySummary(date: today, healthSteps: 12_500, competitionSteps: 12_000)

        let summary = StepsTodaySummary(today: day, goal: 10_000, formatter: formatter)

        #expect(summary.isGoalReached)
        #expect(summary.remainingText == "Tagesziel erreicht!")
        #expect(summary.percentText == "120%")
        #expect(summary.distanceText == nil)
        #expect(summary.energyText == nil)
        #expect(summary.manualStepsNote == "Manuell eingetragene Schritte zählen nicht für Rankings.")
    }

    @Test func weekRunsMondayToSundayWithFutureDaysEmpty() {
        let calendar = Fixtures.activityCalendar
        // Freitag, 16.10.2026: Montag 12. bis heute haben Werte, Sa/So liegen in der Zukunft.
        let days = (0..<7).map { offset in
            DailyActivitySummary(
                date: calendar.adding(offset - 6, to: today),
                healthSteps: 1_000 * (offset + 1),
                competitionSteps: 1_000 * (offset + 1)
            )
        }
        let overview = ActivityOverview(
            today: days[6],
            yesterday: days[5],
            currentWeek: ActivityPeriodSummary(period: .currentWeek, days: Array(days.suffix(5))),
            lastSevenDays: ActivityPeriodSummary(period: .lastSevenDays, days: days),
            updatedAt: Fixtures.date(2026, 10, 16, 12)
        )

        let week = WeekOverview(overview: overview, goal: 10_000, calendar: calendar, formatter: formatter)

        #expect(week.days.map(\.letter) == ["M", "D", "M", "D", "F", "S", "S"])
        #expect(week.days.first?.date == Fixtures.day(2026, 10, 12))
        #expect(week.days.map(\.steps) == [3_000, 4_000, 5_000, 6_000, 7_000, nil, nil])
        #expect(week.days.filter(\.isToday).map(\.date) == [today])
        #expect(week.days[4].level == 0.7)
        #expect(week.accessibilitySummary == "Diese Woche 25.000 Schritte")
    }
}

// MARK: - Platzierungen

@MainActor
struct RegionalStandingsViewModelTests {
    private static let now = Fixtures.date(2026, 10, 17, 12)

    private func makeViewModel(
        profile: UserProfile = Fixtures.profile(regionalLeaderboardEnabled: true),
        leaderboards: LeaderboardRepositoryStub,
        syncing: ActivitySyncingSpy = ActivitySyncingSpy()
    ) -> (RegionalStandingsViewModel, ProfileRepositoryStub) {
        let profiles = ProfileRepositoryStub { $0.profiles[profile.id] = profile }
        let store = ProfileStore(profile: profile, profiles: profiles, regions: RegionRepositoryStub(), cache: InMemoryProfileCache())
        let viewModel = RegionalStandingsViewModel(
            store: store,
            leaderboards: leaderboards,
            syncing: syncing,
            calendar: Fixtures.activityCalendar,
            now: { [now = Self.now] in now }
        )
        return (viewModel, profiles)
    }

    @Test func showsOwnRankOnEveryLevelAndNeighborhood() async throws {
        let leaderboards = LeaderboardRepositoryStub {
            $0.rankings[Fixtures.pfungstadt.id] = Fixtures.ranking(count: 20, currentUserRank: 12, topSteps: 8_552)
            $0.rankings[Fixtures.darmstadtDieburg.id] = Fixtures.ranking(count: 200, currentUserRank: 148)
            $0.rankings[Fixtures.hessen.id] = Fixtures.ranking(count: 3_000, currentUserRank: 2_410)
            $0.rankings[Fixtures.germany.id] = Fixtures.ranking(count: 20_000, currentUserRank: 18_520)
        }
        let syncing = ActivitySyncingSpy()
        let (viewModel, _) = makeViewModel(leaderboards: leaderboards, syncing: syncing)

        await viewModel.loadIfNeeded()

        let standings = try #require(viewModel.standings)
        #expect(standings.scopes.map(\.rankText) == ["#12", "#148", "#2.410", "#18.520"])
        #expect(standings.scopes.map(\.levelTitle) == ["Stadt", "Landkreis", "Bundesland", "Land"])
        #expect(syncing.state.current.flushes == 1)

        let neighborhood = try #require(standings.neighborhood)
        #expect(neighborhood.entries.map(\.rank) == [11, 12, 13])
        // Platz 11 hat 10 Schritte mehr; zum Überholen fehlen 11.
        #expect(neighborhood.stepsToNextPlace == 11)
        #expect(neighborhood.footerText == "Noch 11 Schritte bis Platz #11")
        // Nur die Umgebung wird geladen, nie das ganze Ranking.
        #expect(leaderboards.state.current.pageRequests.isEmpty)
        #expect(leaderboards.state.current.neighborhoodRequests.count == 4)
    }

    @Test func leaderAndLoneUserGetFittingTexts() async throws {
        let leading = LeaderboardRepositoryStub {
            $0.rankings[Fixtures.pfungstadt.id] = Fixtures.ranking(count: 5, currentUserRank: 1)
        }
        let (first, _) = makeViewModel(leaderboards: leading)
        await first.loadIfNeeded()
        let neighborhood = try #require(first.standings?.neighborhood)
        #expect(neighborhood.entries.map(\.rank) == [1, 2, 3])
        #expect(neighborhood.footerText == "Du führst in Pfungstadt.")

        let alone = LeaderboardRepositoryStub {
            $0.rankings[Fixtures.pfungstadt.id] = Fixtures.ranking(count: 1, currentUserRank: 1)
        }
        let (single, _) = makeViewModel(leaderboards: alone)
        await single.loadIfNeeded()
        #expect(single.standings?.neighborhood?.footerText == "Du bist der Erste in Pfungstadt.")
    }

    @Test func notParticipatingShowsNoRanks() async throws {
        let leaderboards = LeaderboardRepositoryStub {
            $0.rankings[Fixtures.pfungstadt.id] = Fixtures.ranking(count: 5)
        }
        let (viewModel, _) = makeViewModel(profile: Fixtures.profile(regionalLeaderboardEnabled: false), leaderboards: leaderboards)

        await viewModel.loadIfNeeded()

        let standings = try #require(viewModel.standings)
        #expect(!standings.isParticipating)
        #expect(standings.scopes.allSatisfy { $0.rank == nil })
        #expect(standings.scopes.first?.rankText == "–")
        #expect(standings.neighborhood == nil)
        // Ohne Zustimmung erscheint der Nutzer nirgends – dafür werden keine Rankings berechnet.
        #expect(leaderboards.state.current.neighborhoodRequests.isEmpty)
    }

    @Test func enablingParticipationReloads() async {
        let leaderboards = LeaderboardRepositoryStub()
        let (viewModel, profiles) = makeViewModel(profile: Fixtures.profile(regionalLeaderboardEnabled: false), leaderboards: leaderboards)
        await viewModel.loadIfNeeded()

        await viewModel.enableParticipation()

        #expect(viewModel.isParticipating)
        #expect(profiles.state.current.optInUpdates == [true])
        #expect(leaderboards.state.current.neighborhoodRequests.count == 4)
    }

    @Test func failedLoadIsNotRetriedOnEveryStepChange() async {
        let leaderboards = LeaderboardRepositoryStub { $0.error = .network }
        let (viewModel, _) = makeViewModel(leaderboards: leaderboards)
        await viewModel.loadIfNeeded()
        let requests = leaderboards.state.current.neighborhoodRequests.count

        await viewModel.refreshIfStale()
        await viewModel.refreshIfStale()

        #expect(leaderboards.state.current.neighborhoodRequests.count == requests)
    }

    @Test func concurrentRequestsShareOneLoad() async {
        let leaderboards = LeaderboardRepositoryStub()
        let (viewModel, _) = makeViewModel(leaderboards: leaderboards)

        async let first: Void = viewModel.load()
        async let second: Void = viewModel.loadIfNeeded()
        async let third: Void = viewModel.refreshIfStale()
        _ = await (first, second, third)

        // Höchstens ein Ladevorgang plus ein zusammengefasstes erneutes Laden.
        let count = leaderboards.state.current.neighborhoodRequests.count
        #expect(count == 4 || count == 8)
        #expect(viewModel.standings != nil)
    }

    @Test func freshDataIsNotReloadedWithinAMinute() async {
        let leaderboards = LeaderboardRepositoryStub()
        let (viewModel, _) = makeViewModel(leaderboards: leaderboards)
        await viewModel.loadIfNeeded()

        await viewModel.refreshIfStale()
        await viewModel.loadIfNeeded()

        #expect(leaderboards.state.current.neighborhoodRequests.count == 4)
    }

    @Test func networkErrorShowsMessage() async {
        let leaderboards = LeaderboardRepositoryStub { $0.error = .network }
        let (viewModel, _) = makeViewModel(leaderboards: leaderboards)

        await viewModel.loadIfNeeded()

        #expect(viewModel.state == .failed(message: "Platzierungen gerade nicht verfügbar. Prüfe deine Verbindung."))
    }

    @Test func windowAroundOwnPlace() {
        #expect(RegionalStandings.window(around: 0, count: 5) == 0...2)
        #expect(RegionalStandings.window(around: 2, count: 5) == 1...3)
        #expect(RegionalStandings.window(around: 4, count: 5) == 2...4)
        #expect(RegionalStandings.window(around: 0, count: 1) == 0...0)
        #expect(RegionalStandings.window(around: 1, count: 2) == 0...1)
    }
}

// MARK: - Dashboard

@MainActor
struct HomeDashboardViewModelTests {
    private func makeStreak(
        activity: HomeViewModel,
        health: HealthServiceStub,
        now: @escaping @Sendable () -> Date = { Fixtures.date(2026, 10, 16, 9) }
    ) -> StepStreakTracker {
        StepStreakTracker(
            history: ActivityHistoryStore(activityData: health, live: activity, calendar: Fixtures.activityCalendar, now: now),
            goals: StepGoalSettings(store: InMemoryStepGoalStore(), calendar: Fixtures.activityCalendar, now: now),
            recordStore: InMemoryStepStreakRecordStore(),
            calendar: Fixtures.activityCalendar,
            now: now
        )
    }

    @Test func greetsWithFirstNameAndComposesSummaries() async {
        let profile = Fixtures.profile(displayName: "Niklas Zockt", regionalLeaderboardEnabled: true)
        let profiles = ProfileRepositoryStub { $0.profiles[profile.id] = profile }
        let store = ProfileStore(profile: profile, profiles: profiles, regions: RegionRepositoryStub(), cache: InMemoryProfileCache())
        let today = Fixtures.day(2026, 10, 16)
        let health = HealthServiceStub { $0.setSteps(8_432, on: today) }
        let activity = HomeViewModel(activityData: health, calendar: Fixtures.activityCalendar, now: { Fixtures.date(2026, 10, 16, 9) })
        let log = NavigationLog()
        let dashboard = HomeDashboardViewModel(
            activity: activity,
            standings: RegionalStandingsViewModel(store: store, leaderboards: LeaderboardRepositoryStub(), syncing: nil),
            settings: HomeSettings(store: InMemoryHomePreferencesStore()),
            streak: makeStreak(activity: activity, health: health),
            activityData: health,
            store: store,
            calendar: Fixtures.activityCalendar,
            formatter: ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: Fixtures.activityCalendar),
            onOpenRankings: { log.rankings.append($0?.id) },
            onOpenSocial: { log.socialOpened += 1 }
        )

        #expect(dashboard.greeting == "Hi Niklas")
        #expect(dashboard.stepsToday == nil)

        await activity.loadIfNeeded()
        #expect(dashboard.stepsToday?.stepsText == "8.432")
        #expect(dashboard.week?.days.count == 7)

        dashboard.goals.setGoal(8_000)
        #expect(dashboard.stepsToday?.isGoalReached == true)
        #expect(dashboard.stepsToday?.goalText == "von 8.000 Schritten")

        let statistics = dashboard.statistics(for: StatisticsRoute(period: .week, metric: .distance))
        #expect(statistics.period == .week)
        #expect(statistics.metric == .distance)

        dashboard.openRankings(Fixtures.hessen)
        dashboard.openSocial()
        #expect(log.rankings == [Fixtures.hessen.id])
        #expect(log.socialOpened == 1)

        dashboard.present(.customize)
        #expect(dashboard.presentedSheet == .customize)
    }

    @Test func hiddenRankSectionsLoadNoRankings() async {
        let profile = Fixtures.profile(regionalLeaderboardEnabled: true)
        let profiles = ProfileRepositoryStub { $0.profiles[profile.id] = profile }
        let store = ProfileStore(profile: profile, profiles: profiles, regions: RegionRepositoryStub(), cache: InMemoryProfileCache())
        let leaderboards = LeaderboardRepositoryStub()
        let settings = HomeSettings(store: InMemoryHomePreferencesStore())
        settings.setVisible(false, for: .regionRanks)
        settings.setVisible(false, for: .neighborhood)
        let health = HealthServiceStub()
        let activity = HomeViewModel(activityData: health, calendar: Fixtures.activityCalendar)
        let dashboard = HomeDashboardViewModel(
            activity: activity,
            standings: RegionalStandingsViewModel(store: store, leaderboards: leaderboards, syncing: nil),
            settings: settings,
            streak: makeStreak(activity: activity, health: health),
            activityData: health,
            store: store
        )

        await dashboard.loadIfNeeded()
        await dashboard.stepsDidChange()
        await dashboard.returnedToForeground()

        #expect(!dashboard.showsStandings)
        #expect(leaderboards.state.current.neighborhoodRequests.isEmpty)
    }

    @Test func foregroundReadsStepsBeforeRankings() async {
        let profile = Fixtures.profile(regionalLeaderboardEnabled: true)
        let profiles = ProfileRepositoryStub { $0.profiles[profile.id] = profile }
        let store = ProfileStore(profile: profile, profiles: profiles, regions: RegionRepositoryStub(), cache: InMemoryProfileCache())
        let syncing = ActivitySyncingSpy()
        let health = HealthServiceStub { $0.setSteps(5_000, on: Fixtures.day(2026, 10, 16)) }
        let activity = HomeViewModel(activityData: health, syncing: syncing, calendar: Fixtures.activityCalendar, now: { Fixtures.date(2026, 10, 16, 9) })
        let dashboard = HomeDashboardViewModel(
            activity: activity,
            standings: RegionalStandingsViewModel(store: store, leaderboards: LeaderboardRepositoryStub(), syncing: syncing),
            settings: HomeSettings(store: InMemoryHomePreferencesStore()),
            streak: makeStreak(activity: activity, health: health),
            activityData: health,
            store: store
        )

        await dashboard.returnedToForeground()

        // Die neuen Schritte sind übergeben, bevor die Platzierungen (mit flush) geladen werden.
        #expect(syncing.triggers == [.foreground])
        #expect(syncing.state.current.flushes == 1)
        #expect(dashboard.standings.standings != nil)
    }
}

@MainActor
private final class NavigationLog {
    var rankings: [RegionID?] = []
    var socialOpened = 0
}
