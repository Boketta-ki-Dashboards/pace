import ActivityFeature
import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
import SocialFeature
import Testing

// MARK: - Einstellungen

@MainActor
struct HomeSettingsTests {
    private func kinds(_ settings: HomeSettings) -> [HomeModuleKind] {
        settings.modules.map(\.kind)
    }

    @Test func defaultLayoutHasAllModulesInMediumSize() {
        let settings = HomeSettings(store: InMemoryHomePreferencesStore())

        #expect(kinds(settings) == [.regionRanks, .stepsToday, .week, .streak, .neighborhood, .friends, .groups])
        #expect(settings.modules.allSatisfy { $0.size == .medium })
        #expect(settings.modules.first { $0.kind == .neighborhood }?.regionLevel == .municipality)
        #expect(settings.modules.first { $0.kind == .week }?.regionLevel == nil)
        #expect(settings.addableKinds == [.neighborhood])
    }

    @Test func versionOneLayoutIsMigrated() throws {
        // Version 1: sichtbare und ausgeblendete Bereiche, dazu das alte Tagesziel.
        let json = #"""
        {"stepGoal": 12500, "sections": [
          {"section": "stepsToday", "isVisible": true},
          {"section": "regionRanks", "isVisible": false},
          {"section": "week", "isVisible": true},
          {"section": "neighborhood", "isVisible": true},
          {"section": "friends", "isVisible": false},
          {"section": "groups", "isVisible": true}
        ]}
        """#
        let preferences = try JSONDecoder().decode(HomePreferences.self, from: Data(json.utf8))

        #expect(preferences.legacyStepGoal == 12_500)
        // Reihenfolge bleibt, Ausgeblendetes entfällt, die neue Serie kommt nach der Woche.
        #expect(preferences.modules.map(\.kind) == [.stepsToday, .week, .streak, .neighborhood, .groups])
        #expect(preferences.modules.allSatisfy { $0.size == .medium })

        // Gespeichert wird danach Version 2 – inklusive des alten Ziels, bis der Zielverlauf es übernommen hat.
        let reloaded = try JSONDecoder().decode(HomePreferences.self, from: JSONEncoder().encode(preferences))
        #expect(reloaded == preferences)
    }

    @Test func modulesCanBeAddedRemovedResizedAndScoped() throws {
        let store = InMemoryHomePreferencesStore()
        let settings = HomeSettings(store: store)
        let friends = settings.modules.first { $0.kind == .friends }!

        settings.remove(friends.id)
        #expect(!kinds(settings).contains(.friends))
        #expect(settings.addableKinds.contains(.friends))

        let district = settings.add(.neighborhood)
        #expect(district != nil)
        settings.setRegionLevel(.district, for: district!.id)
        settings.setSize(.large, for: district!.id)
        #expect(settings.modules.last?.detailText == "Groß · Kreis")
        #expect(settings.add(.week) == nil) // gibt es schon

        // Die Schrittkarte lässt sich weder entfernen noch verkleinern.
        let steps = settings.modules.first { $0.kind == .stepsToday }!
        settings.remove(steps.id)
        settings.setSize(.small, for: steps.id)
        #expect(settings.modules.first { $0.kind == .stepsToday }?.size == .medium)

        #expect(HomeSettings(store: store).modules == settings.modules)
    }

    @Test func neighborhoodRadiiFollowTheModules() {
        let settings = HomeSettings(store: InMemoryHomePreferencesStore())
        #expect(settings.neighborhoodRadii == [.municipality: 2])

        let municipality = settings.modules.first { $0.kind == .neighborhood }!
        settings.setSize(.small, for: municipality.id)
        #expect(settings.neighborhoodRadii == [.municipality: 1])

        let state = settings.add(.neighborhood)!
        settings.setRegionLevel(.state, for: state.id)
        settings.setSize(.large, for: state.id)
        #expect(settings.neighborhoodRadii == [.municipality: 1, .state: 4])

        settings.remove(municipality.id)
        settings.remove(state.id)
        #expect(settings.neighborhoodRadii.isEmpty)
        #expect(settings.showsStandings) // Platzierungs-Karten zeigen weiterhin Ränge
        settings.remove(settings.modules.first { $0.kind == .regionRanks }!.id)
        #expect(!settings.showsStandings)
    }

    @Test func modulesCanBeReorderedAndReset() {
        let settings = HomeSettings(store: InMemoryHomePreferencesStore())

        settings.moveModules(fromOffsets: [1], toOffset: 0)
        #expect(kinds(settings).prefix(2) == [.stepsToday, .regionRanks])

        settings.moveModules(fromOffsets: [6], toOffset: 2)
        #expect(kinds(settings) == [.stepsToday, .regionRanks, .groups, .week, .streak, .neighborhood, .friends])

        settings.resetLayout()
        #expect(kinds(settings) == [.regionRanks, .stepsToday, .week, .streak, .neighborhood, .friends, .groups])
    }

    @Test func storedPreferencesAreRepaired() throws {
        let json = #"""
        {"version": 2, "modules": [
          {"id": "a", "kind": "week", "size": "large"},
          {"id": "b", "kind": "week", "size": "small"},
          {"id": "c", "kind": "neighborhood", "size": "small"},
          {"id": "c", "kind": "friends", "size": "small"},
          {"id": "d", "kind": "challenges", "size": "medium"},
          {"id": "e", "kind": "regionRanks", "size": "medium"}
        ]}
        """#
        let decoded = try JSONDecoder().decode(HomePreferences.self, from: Data(json.utf8))
        let settings = HomeSettings(store: InMemoryHomePreferencesStore(decoded))

        // Doppelte Woche und doppelte ID entfallen, unbekannte Art wird übersprungen, die Schrittkarte ergänzt.
        #expect(kinds(settings) == [.week, .neighborhood, .regionRanks, .stepsToday])
        #expect(settings.modules[1].regionLevel == .municipality)
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
        #expect(summary.flightsText == nil)
        #expect(summary.exerciseText == nil)
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

        var goals = StepGoalHistory(initialGoal: 10_000)
        goals.setGoal(4_000, from: Fixtures.day(2026, 10, 14))
        let week = WeekOverview(overview: overview, goals: goals, calendar: calendar, formatter: formatter)

        #expect(week.days.map(\.letter) == ["M", "D", "M", "D", "F", "S", "S"])
        #expect(week.days.first?.date == Fixtures.day(2026, 10, 12))
        #expect(week.days.map(\.steps) == [3_000, 4_000, 5_000, 6_000, 7_000, nil, nil])
        #expect(week.days.filter(\.isToday).map(\.date) == [today])
        // Skala: Ziel von heute (4.000) bzw. bester Tag (7.000).
        #expect(week.days[4].level == 1)
        #expect(week.days[2].level == 5_000.0 / 7_000)
        #expect(week.accessibilitySummary == "Diese Woche 25.000 Schritte")
        #expect(week.totalText == "25.000")
        #expect(week.averageText == "Ø 5.000 pro Tag")
        // Mo/Di (3.000/4.000 bei 10.000) verfehlt, ab Mi (Ziel 4.000) erreicht; heute erreicht → zählt mit.
        #expect(week.days.map(\.reachedGoal) == [false, false, true, true, true, false, false])
        #expect(week.goalDaysText == "3 von 5 Tagen Ziel erreicht")
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

    @Test func neighborhoodModulesLoadTheRowsTheyNeedPerLevel() async throws {
        let leaderboards = LeaderboardRepositoryStub {
            $0.rankings[Fixtures.pfungstadt.id] = Fixtures.ranking(count: 20, currentUserRank: 12, topSteps: 8_552)
            $0.rankings[Fixtures.darmstadtDieburg.id] = Fixtures.ranking(count: 200, currentUserRank: 2)
            $0.rankings[Fixtures.hessen.id] = Fixtures.ranking(count: 3_000, currentUserRank: 2_410)
            $0.rankings[Fixtures.germany.id] = Fixtures.ranking(count: 20_000, currentUserRank: 18_520)
        }
        let (viewModel, _) = makeViewModel(leaderboards: leaderboards)
        // Klein in der Gemeinde (nur der eigene Platz + Abstand), groß im Kreis (fünf Zeilen).
        viewModel.neighborhoodRadii = [.municipality: 1, .district: 4]

        await viewModel.loadIfNeeded()

        let radii = Dictionary(uniqueKeysWithValues: leaderboards.state.current.neighborhoodRequests.map {
            ($0.query.regionID, $0.radius)
        })
        #expect(radii == [
            Fixtures.pfungstadt.id: 1, Fixtures.darmstadtDieburg.id: 4, Fixtures.hessen.id: 0, Fixtures.germany.id: 0,
        ])
        let standings = try #require(viewModel.standings)
        let small = try #require(standings.neighborhood(for: .municipality, rows: 1))
        #expect(small.entries.map(\.rank) == [12])
        #expect(small.footerText == "Noch 11 Schritte bis Platz #11")
        // Platz 2 im Kreis: ein Platz darüber, drei darunter.
        let large = try #require(standings.neighborhood(for: .district, rows: 5))
        #expect(large.entries.map(\.rank) == [1, 2, 3, 4, 5])
        #expect(standings.neighborhood(for: .state, rows: 3)?.entries.map(\.rank) == [2_410])

        // Mehr Zeilen nötig → neu laden.
        viewModel.neighborhoodRadii = [.municipality: 2]
        await viewModel.loadIfNeeded()
        #expect(leaderboards.state.current.neighborhoodRequests.count == 8)
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
        #expect(RegionalStandings.window(around: 0, count: 10, size: 5) == 0...4)
        #expect(RegionalStandings.window(around: 5, count: 10, size: 5) == 3...7)
        #expect(RegionalStandings.window(around: 9, count: 10, size: 5) == 5...9)
        #expect(RegionalStandings.window(around: 4, count: 10, size: 1) == 4...4)
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
            social: SocialViewModel(repository: nil),
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
        for module in settings.modules where module.kind == .regionRanks || module.kind == .neighborhood {
            settings.remove(module.id)
        }
        let health = HealthServiceStub()
        let activity = HomeViewModel(activityData: health, calendar: Fixtures.activityCalendar)
        let dashboard = HomeDashboardViewModel(
            activity: activity,
            standings: RegionalStandingsViewModel(store: store, leaderboards: leaderboards, syncing: nil),
            settings: settings,
            streak: makeStreak(activity: activity, health: health),
            social: SocialViewModel(repository: nil),
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
            social: SocialViewModel(repository: nil),
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

// MARK: - Serie

struct StreakSummaryTests {
    private let formatter = ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: Fixtures.activityCalendar)
    private let today = Fixtures.day(2026, 10, 16)

    private func recent(_ statuses: [StepStreakDayStatus]) -> [(day: LocalDate, status: StepStreakDayStatus)] {
        statuses.enumerated().map { index, status in
            (Fixtures.activityCalendar.adding(index - (statuses.count - 1), to: today), status)
        }
    }

    @Test func runningStreakWaitsForToday() {
        let streak = StepStreak(
            current: 5, currentStart: Fixtures.day(2026, 10, 11), isTodayReached: false,
            longest: 9, longestRange: Fixtures.day(2026, 9, 1)...Fixtures.day(2026, 9, 9), reachesHistoryStart: false
        )
        let record = StepStreakRecord(days: 12, start: Fixtures.day(2026, 3, 1), end: Fixtures.day(2026, 3, 12))

        let summary = StreakSummary(
            streak: streak,
            record: record,
            recentDays: recent([.missed, .reached, .reached, .reached, .reached, .reached, .pending]),
            formatter: formatter
        )

        #expect(summary.currentText == "5 Tage")
        #expect(summary.statusText == "Erreiche heute dein Tagesziel, um deine Serie fortzusetzen.")
        #expect(summary.recordText == "Rekord: 12 Tage")
        // Kalenderwoche Montag bis Sonntag; Samstag und Sonntag liegen noch in der Zukunft.
        #expect(summary.lastWeek.map(\.letter) == ["M", "D", "M", "D", "F", "S", "S"])
        #expect(summary.lastWeek.map(\.status) == [.reached, .reached, .reached, .reached, .pending, .future, .future])
        #expect(summary.lastWeek[4].accessibilityLabel == "Freitag, 16. Oktober: heute noch offen")
        #expect(summary.lastFourWeeks.count == 28)
        #expect(summary.lastFourWeeks.first?.date == Fixtures.day(2026, 9, 21))
        #expect(summary.lastFourWeeks.first?.status == .unknown)
        #expect(summary.lastFourWeeks[19].status == .missed)
    }

    @Test func reachedTodayAndOpenEndedStreaks() {
        let reached = StreakSummary(
            streak: StepStreak(current: 1, currentStart: today, isTodayReached: true, longest: 1, longestRange: today...today, reachesHistoryStart: false),
            record: nil,
            recentDays: recent([.reached]),
            formatter: formatter
        )
        #expect(reached.currentText == "1 Tag")
        #expect(reached.statusText == "Heute geschafft – weiter so!")
        #expect(reached.recordText == nil)

        let openEnded = StreakSummary(
            streak: StepStreak(current: 400, currentStart: Fixtures.day(2025, 10, 1), isTodayReached: true, longest: 400, longestRange: nil, reachesHistoryStart: true),
            record: nil,
            recentDays: [],
            formatter: formatter
        )
        #expect(openEnded.currentText == "400+ Tage")

        let none = StreakSummary(streak: .empty, record: nil, recentDays: [], formatter: formatter)
        #expect(none.statusText == "Erreiche heute dein Tagesziel, um eine neue Serie zu starten.")
        #expect(none.lastWeek.isEmpty)
    }
}
