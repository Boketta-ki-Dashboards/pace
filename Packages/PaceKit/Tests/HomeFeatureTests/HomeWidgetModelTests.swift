import ActivityFeature
import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
import Testing

// MARK: - Regionale Karten

struct HomeRegionCardsTests {
    private func standings(_ hierarchy: RegionHierarchy, ranks: [RegionID: Int], radius: Int = 0) -> RegionalStandings {
        var neighborhoods: [RegionID: [LeaderboardEntry]] = [:]
        for scope in hierarchy.leaderboardScopes {
            guard let rank = ranks[scope.id] else { continue }
            let all = Fixtures.ranking(count: rank + 5, currentUserRank: rank, topSteps: 20_000)
            neighborhoods[scope.id] = all.filter { abs($0.rank - rank) <= radius }
        }
        let radii = Dictionary(uniqueKeysWithValues: hierarchy.leaderboardScopes.map { ($0.level, radius) })
        return RegionalStandings(scopes: hierarchy.leaderboardScopes, neighborhoods: neighborhoods, radii: radii, isParticipating: true)
    }

    @Test func districtTownShowsFourLevelsWithOwnRankings() {
        let hierarchy = Fixtures.pfungstadtHierarchy
        let cards = HomeRegionCards.cards(
            hierarchy: hierarchy,
            standings: standings(hierarchy, ranks: [
                Fixtures.pfungstadt.id: 12, Fixtures.darmstadtDieburg.id: 148, Fixtures.hessen.id: 2_410, Fixtures.germany.id: 18_520,
            ], radius: 1)
        )

        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(cards.map(\.title) == ["Stadt", "Landkreis", "Bundesland", "Land"])
            #expect(cards.map(\.name) == ["Pfungstadt", "Darmstadt-Dieburg", "Hessen", "Deutschland"])
            #expect(cards.map(\.rankText) == ["#12", "#148", "#2.410", "#18.520"])
            #expect(cards.allSatisfy { !$0.sharesSmallerRanking })
            // Mit Nachbarn geladen: Abstand zum Platz darüber (Fixtures: 10 Schritte Abstand + 1).
            #expect(cards[0].stepsToNextPlace == 11)
            #expect(cards[0].nextPlaceShortText == "+11 bis #11")
            #expect(cards[0].nextPlaceText == "Noch 11 Schritte bis Platz #11")
            #expect(cards[0].accessibilityLabel == "Stadt Pfungstadt, Platz 12")
        }
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(cards.map(\.title) == ["City", "District", "State", "Country"])
            #expect(cards.map(\.rankText) == ["#12", "#148", "#2,410", "#18,520"])
            #expect(cards[0].nextPlaceText == "11 steps to rank #11")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(cards.map(\.title) == ["Город", "Район", "Земля", "Страна"])
            #expect(cards[0].nextPlaceText == "Ещё 11 шагов до места #11")
        }
    }

    @Test func independentCityKeepsFourCardsWithTheSameRank() {
        let hierarchy = Fixtures.frankfurtHierarchy
        #expect(hierarchy.leaderboardScopes.count == 3)
        let cards = HomeRegionCards.cards(
            hierarchy: hierarchy,
            standings: standings(hierarchy, ranks: [Fixtures.frankfurt.id: 40, Fixtures.hessen.id: 900, Fixtures.germany.id: 9_000])
        )

        #expect(cards.count == 4)
        #expect(cards.map(\.level) == [.municipality, .district, .state, .country])
        #expect(cards[1].rank == 40)
        #expect(cards[1].rankingRegion?.id == Fixtures.frankfurt.id)
        #expect(cards[1].sharesSmallerRanking)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(cards.map(\.title) == ["Stadt", "Kreisfreie Stadt", "Bundesland", "Land"])
            #expect(cards.map(\.rankText) == ["#40", "#40", "#900", "#9.000"])
        }
    }

    @Test func cityStateKeepsFourCardsWithTheSameRank() {
        let hierarchy = Fixtures.berlinHierarchy
        #expect(hierarchy.leaderboardScopes.count == 2)
        let cards = HomeRegionCards.cards(
            hierarchy: hierarchy,
            standings: standings(hierarchy, ranks: [Fixtures.berlin.id: 7, Fixtures.germany.id: 5_000])
        )

        #expect(cards.count == 4)
        #expect(cards.map(\.rank) == [7, 7, 7, 5_000])
        #expect(cards.map { $0.rankingRegion?.id } == [Fixtures.berlin.id, Fixtures.berlin.id, Fixtures.berlin.id, Fixtures.germany.id])
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(cards.map(\.title) == ["Stadt", "Kreisfreie Stadt", "Stadtstaat", "Land"])
            #expect(cards.map(\.name) == ["Berlin", "Berlin", "Berlin", "Deutschland"])
        }
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(cards[2].title == "City state")
        }
    }

    @Test func withoutRegionOrStandingsTheCardsStayNeutral() {
        let placeholders = HomeRegionCards.cards(hierarchy: nil, standings: nil)
        #expect(placeholders.count == 4)
        #expect(placeholders.allSatisfy { $0.rank == nil && $0.name.isEmpty && $0.rankingRegion == nil })
        #expect(placeholders.map(\.rankText) == ["–", "–", "–", "–"])

        let unranked = HomeRegionCards.cards(hierarchy: Fixtures.pfungstadtHierarchy, standings: nil)
        #expect(unranked.allSatisfy { $0.rank == nil && $0.stepsToNextPlace == nil })
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(unranked[0].accessibilityLabel == "Stadt Pfungstadt, noch nicht platziert")
        }
    }

    @Test func selectedLevelsKeepTheirOrder() {
        let cards = HomeRegionCards.cards(hierarchy: Fixtures.pfungstadtHierarchy, standings: nil, levels: [.country, .municipality])
        #expect(cards.map(\.level) == [.municipality, .country])
    }

    @Test func leaderGetsTopSpotTexts() {
        let hierarchy = Fixtures.pfungstadtHierarchy
        let cards = HomeRegionCards.cards(hierarchy: hierarchy, standings: standings(hierarchy, ranks: [Fixtures.pfungstadt.id: 1], radius: 1))
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(cards[0].nextPlaceShortText == "Spitze")
            #expect(cards[0].nextPlaceText == "Du führst hier.")
        }
    }
}

// MARK: - Freunde

struct HomeFriendsWidgetTests {
    private let me = LeaderboardEntry(rank: 3, publicUserID: Fixtures.publicUserID, username: "niklas", displayName: "Niklas", competitionSteps: 8_432, isCurrentUser: true)

    private func friend(_ index: Int, _ name: String, _ steps: Int, rank: Int) -> LeaderboardEntry {
        LeaderboardEntry(
            rank: rank,
            publicUserID: UUID(uuidString: String(format: "40000000-0000-4000-8000-%012d", index))!,
            username: name.lowercased(),
            displayName: name,
            competitionSteps: steps,
            isCurrentUser: false
        )
    }

    private var ranking: [LeaderboardEntry] {
        [
            friend(1, "Leon", 12_480, rank: 1),
            friend(2, "Marie", 10_920, rank: 2),
            me,
            friend(3, "Tim", 7_921, rank: 4),
            friend(4, "Anna", 6_104, rank: 5),
            friend(5, "Gotscha", 5_000, rank: 6),
            friend(6, "Paul", 4_000, rank: 7),
        ]
    }

    @Test func selectionShowsOnlyChosenFriendsAndYouWithNewRanks() {
        let gotscha = ranking[5].publicUserID, marie = ranking[1].publicUserID
        let widget = HomeFriendsWidget(ranking: ranking, friendIDs: Set(ranking.map(\.publicUserID)), selection: [gotscha, marie])

        #expect(widget.allRows.map(\.entry.displayName) == ["Marie", "Niklas", "Gotscha"])
        #expect(widget.allRows.map(\.rank) == [1, 2, 3])
        #expect(widget.hasFriends)
        #expect(!widget.isAllFriends)
        #expect(widget.missingCount == 0)
        #expect(widget.missingText == nil)
    }

    @Test func sizesShowTopOneThreeFiveAndAlwaysYou() {
        let widget = HomeFriendsWidget(ranking: ranking, friendIDs: nil, selection: nil)

        #expect(widget.isAllFriends)
        #expect(widget.rows(for: .small).map(\.entry.displayName) == ["Leon"])
        #expect(widget.rows(for: .medium).map(\.entry.displayName) == ["Leon", "Marie", "Niklas"])
        #expect(widget.rows(for: .large).map(\.entry.displayName) == ["Leon", "Marie", "Niklas", "Tim", "Anna"])
        #expect(widget.rows(for: .max).count == 5)
        #expect(widget.chartRows.count == 7)

        // Liegst du weiter hinten, ersetzt deine Zeile ab Mittel die letzte.
        let behind = ranking.map { entry in
            entry.isCurrentUser
                ? LeaderboardEntry(rank: 7, publicUserID: entry.publicUserID, username: "niklas", displayName: "Niklas", competitionSteps: 100, isCurrentUser: true)
                : entry
        }
        let trailing = HomeFriendsWidget(ranking: behind, friendIDs: nil, selection: nil)
        #expect(trailing.rows(for: .medium).map(\.entry.displayName) == ["Leon", "Marie", "Niklas"])
        #expect(trailing.rows(for: .medium).last?.rank == 7)
        #expect(trailing.rows(for: .small).map(\.entry.displayName) == ["Leon"])
    }

    @Test func removedFriendsAreReportedInsteadOfShown() {
        let gone = UUID()
        let marie = ranking[1].publicUserID
        let widget = HomeFriendsWidget(ranking: ranking, friendIDs: Set(ranking.filter { !$0.isCurrentUser }.map(\.publicUserID)), selection: [gone, marie])

        #expect(widget.allRows.map(\.entry.displayName) == ["Marie", "Niklas"])
        #expect(widget.missingCount == 1)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(widget.missingText == "1 ausgewählte Person ist nicht mehr in deiner Freundesliste.")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(widget.missingText == "1 выбранный человек больше не в списке друзей.")
        }

        // Alle Ausgewählten weg: nur du – und der Hinweis.
        let empty = HomeFriendsWidget(ranking: [me], friendIDs: [], selection: [gone])
        #expect(empty.allRows.map(\.entry.isCurrentUser) == [true])
        #expect(!empty.hasFriends)
        #expect(empty.missingCount == 1)

        // Solange die Freundesliste nicht geladen ist, gilt niemand als entfernt.
        #expect(HomeFriendsWidget(ranking: [], friendIDs: nil, selection: [gone]).missingCount == 0)
    }
}

// MARK: - Gruppen

struct HomeGroupSelectionTests {
    @Test func resolvesAllSingleAndMissingGroups() {
        let klasse = SocialRepositoryStub.group(name: "Klasse 8b")
        let buero = SocialRepositoryStub.group(name: "Laufteam Büro")

        #expect(HomeGroupSelection(groupID: nil, groups: [klasse, buero], isLoaded: true) == .all([klasse, buero]))
        #expect(HomeGroupSelection(groupID: buero.id, groups: [klasse, buero], isLoaded: true) == .single(buero))
        // Gruppe verlassen oder gelöscht: Hinweis statt leerer Karte.
        #expect(HomeGroupSelection(groupID: UUID(), groups: [klasse], isLoaded: true) == .missing)
        // Vor dem Laden gilt sie noch nicht als gelöscht.
        #expect(HomeGroupSelection(groupID: UUID(), groups: [], isLoaded: false) == .all([]))
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(HomeGroupSelection.missingText.hasPrefix("This group is no longer available."))
            #expect(HomeGroupTexts.members(1) == "1 member")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(HomeGroupTexts.members(3) == "3 участника")
        }
    }
}

// MARK: - Streak

struct HomeStreakWidgetTests {
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

        let widget = HomeStreakWidget(
            streak: streak,
            record: record,
            recentDays: recent([.missed, .reached, .reached, .reached, .reached, .reached, .pending]),
            formatter: formatter
        )

        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(widget.currentText == "5 Tage")
            #expect(widget.currentNumberText == "5")
            #expect(widget.statusText == "Erreiche heute dein Tagesziel, um deine Serie fortzusetzen.")
            #expect(widget.recordText == "12 Tage")
            #expect(widget.shortStatusText == "Heute offen")
            // Kalenderwoche Montag bis Sonntag; Samstag und Sonntag liegen noch in der Zukunft.
            #expect(widget.week.map(\.letter) == ["M", "D", "M", "D", "F", "S", "S"])
            #expect(widget.week.map(\.status) == [.reached, .reached, .reached, .reached, .pending, .future, .future])
            #expect(widget.week[4].isToday)
            #expect(widget.week[4].accessibilityLabel == "Freitag, 16. Oktober: heute noch offen")
            #expect(widget.accessibilityLabel == "Persönliche Serie: 5 Tage. Erreiche heute dein Tagesziel, um deine Serie fortzusetzen. Rekord: 12 Tage.")
        }
        #expect(widget.fourWeeks.count == 28)
        #expect(widget.fourWeeks.first?.date == Fixtures.day(2026, 9, 21))
        #expect(widget.fourWeeks.first?.status == .unknown)
        #expect(widget.fourWeeks[19].status == .missed)
        #expect(widget.reachedThisWeek == 4)
        #expect(widget.reachedLast30Days == 5)
    }

    @Test func brokenStreakStillShowsReachedDaysClearly() {
        // Heute offen, gestern verpasst – vorher in dieser Woche zweimal erreicht.
        let widget = HomeStreakWidget(
            streak: StepStreak(current: 0, currentStart: nil, isTodayReached: false, longest: 2, longestRange: nil, reachesHistoryStart: false),
            record: StepStreakRecord(days: 4, start: Fixtures.day(2026, 9, 1), end: Fixtures.day(2026, 9, 4)),
            recentDays: recent([.reached, .reached, .missed, .pending]),
            formatter: formatter
        )
        #expect(widget.current == 0)
        #expect(widget.reachedThisWeek == 2)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(widget.currentText == "0 Tage")
            #expect(widget.statusText == "Gerade keine laufende Serie – diese Woche hast du dein Ziel an 2 Tagen erreicht.")
        }
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(widget.statusText == "No active streak right now – you reached your goal on 2 days this week.")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(widget.statusText == "Сейчас серии нет – на этой неделе цель выполнена 2 раза.")
            #expect(widget.currentText == "0 дней")
        }
    }

    @Test func reachedTodayAndOpenEndedStreaks() {
        let reached = HomeStreakWidget(
            streak: StepStreak(current: 1, currentStart: today, isTodayReached: true, longest: 1, longestRange: today...today, reachesHistoryStart: false),
            record: nil,
            recentDays: recent([.reached]),
            formatter: formatter
        )
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(reached.currentText == "1 Tag")
            #expect(reached.statusText == "Heute geschafft – weiter so!")
            #expect(reached.recordText == nil)
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(reached.currentText == "1 день")
        }

        let openEnded = HomeStreakWidget(
            streak: StepStreak(current: 400, currentStart: Fixtures.day(2025, 10, 1), isTodayReached: true, longest: 400, longestRange: nil, reachesHistoryStart: true),
            record: nil,
            recentDays: [],
            formatter: formatter
        )
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(openEnded.currentText == "400+ Tage")
        }
        #expect(openEnded.week.isEmpty)

        let none = HomeStreakWidget(streak: .empty, record: nil, recentDays: [], formatter: formatter)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(none.statusText == "Erreiche heute dein Tagesziel, um eine neue Serie zu starten.")
        }
    }
}

// MARK: - Kalender

struct HomeCalendarWidgetTests {
    private let formatter = ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: Fixtures.activityCalendar)
    private let today = Fixtures.day(2026, 10, 16)

    private func steps(_ values: [LocalDate: Int]) -> (LocalDate) -> Int? {
        { values[$0] }
    }

    @Test func weekUsesHistoricGoalsRingsAndFutureDays() throws {
        var goals = StepGoalHistory(initialGoal: 10_000)
        goals.setGoal(6_000, from: Fixtures.day(2026, 10, 14))
        let values: [LocalDate: Int] = [
            Fixtures.day(2026, 10, 12): 11_000, // Ziel 10.000 erreicht
            Fixtures.day(2026, 10, 13): 8_000, // Ziel damals 10.000 → nicht erreicht
            Fixtures.day(2026, 10, 14): 6_500, // neues Ziel 6.000 → erreicht
            today: 3_000,
        ]

        let widget = HomeCalendarWidget(size: .small, today: today, goals: goals, formatter: formatter, daySteps: steps(values))

        #expect(widget.weeks.count == 1)
        let days = try #require(widget.weeks.first)
        #expect(days.map(\.date.day) == [12, 13, 14, 15, 16, 17, 18])
        #expect(days.map(\.state) == [.reached, .notReached, .reached, .noData, .notReached, .future, .future])
        #expect(days[1].progress == 0.8)
        #expect(days[4].isToday)
        #expect(days[4].progress == 0.5)
        #expect(days[5].steps == nil)
        #expect(widget.weekdayLetters == ["M", "D", "M", "D", "F", "S", "S"])
        #expect(widget.reachedCount == 2)
        #expect(widget.elapsedCount == 5)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(widget.summaryText == "2 von 5 Tagen erreicht")
            #expect(days[0].accessibilityLabel == "Montag, 12. Oktober, Ziel erreicht, 11.000 Schritte")
            #expect(days[4].accessibilityLabel == "Freitag, 16. Oktober, heute, Ziel nicht erreicht, 3.000 Schritte")
        }
    }

    @Test func sizesShowWeekTwoWeeksOrMonth() {
        let goals = StepGoalHistory(initialGoal: 10_000)
        let medium = HomeCalendarWidget(size: .medium, today: today, goals: goals, formatter: formatter) { _ in 12_000 }
        #expect(medium.weeks.count == 2)
        #expect(medium.weeks.first?.first?.date == Fixtures.day(2026, 10, 5))

        let month = HomeCalendarWidget(size: .large, today: today, goals: goals, formatter: formatter) { _ in 12_000 }
        // Oktober 2026 beginnt an einem Donnerstag und endet an einem Samstag: fünf Wochenzeilen.
        #expect(month.weeks.count == 5)
        #expect(month.weeks.allSatisfy { $0.count == 7 })
        #expect(month.weeks.first?.first?.date == Fixtures.day(2026, 9, 28))
        #expect(month.weeks.first?.first?.isInPeriod == false)
        #expect(month.periodTitle == "Oktober 2026")
        #expect(month.elapsedCount == 16)
        #expect(month.reachedCount == 16)
        #expect(HomeCalendarWidget(size: .max, today: today, goals: goals, formatter: formatter) { _ in nil }.reachedCount == 0)
    }
}

// MARK: - Aktivität und Schrittkarte

struct HomeActivityWidgetTests {
    private let formatter = ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: Fixtures.activityCalendar)
    private let today = Fixtures.day(2026, 10, 16)

    private var overview: ActivityOverview {
        let days = (0..<7).map { offset in
            DailyActivitySummary(
                date: Fixtures.activityCalendar.adding(offset - 6, to: today),
                healthSteps: 1_000 * (offset + 1),
                competitionSteps: 1_000 * (offset + 1),
                walkingRunningDistanceMeters: offset == 3 ? nil : Double(700 * (offset + 1)),
                activeEnergyKilocalories: Double(40 * (offset + 1))
            )
        }
        return ActivityOverview(
            today: days[6],
            yesterday: days[5],
            currentWeek: ActivityPeriodSummary(period: .currentWeek, days: Array(days.suffix(5))),
            lastSevenDays: ActivityPeriodSummary(period: .lastSevenDays, days: days),
            updatedAt: Fixtures.date(2026, 10, 16, 12)
        )
    }

    @Test func stepsDistanceAndCaloriesOfTheLastSevenDays() {
        let steps = HomeActivityWidget(metric: .steps, overview: overview, formatter: formatter)
        #expect(steps.days.count == 7)
        #expect(steps.days.last?.isToday == true)
        #expect(steps.todayText == "7.000")
        #expect(steps.totalText == "28.000")
        #expect(steps.averageText == "4.000")
        #expect(steps.bestDayText == "Fr · 7.000")
        #expect(steps.maximum == 7_000)

        let distance = HomeActivityWidget(metric: .distance, overview: overview, formatter: formatter)
        // Ein Tag ohne lesbare Distanz bleibt leer statt 0.
        #expect(distance.days[3].value == nil)
        #expect(distance.todayText == "4,9 km")

        let energy = HomeActivityWidget(metric: .activeEnergy, overview: overview, formatter: formatter)
        #expect(energy.todayText == "280 kcal")
    }

    /// Heute gemessen (Apple Watch), an einem früheren Tag nur geschätzt: Summe/Durchschnitt mit „≈“, der heutige Wert
    /// und seine Beschriftung aber als gemessen (Prüfbefund Auftrag 4).
    @Test func todayCaptionFollowsTodaysSource() {
        let days = (0..<7).map { offset in
            DailyActivitySummary(
                date: Fixtures.activityCalendar.adding(offset - 6, to: today),
                healthSteps: 5_000,
                competitionSteps: 5_000,
                activeEnergyKilocalories: offset == 0 ? nil : 300,
                estimatedActiveEnergyKilocalories: offset == 0 ? 200 : nil
            )
        }
        let mixed = ActivityOverview(
            today: days[6],
            yesterday: days[5],
            currentWeek: ActivityPeriodSummary(period: .currentWeek, days: Array(days.suffix(5))),
            lastSevenDays: ActivityPeriodSummary(period: .lastSevenDays, days: days),
            updatedAt: Fixtures.date(2026, 10, 16, 12)
        )
        let energy = HomeActivityWidget(metric: .activeEnergy, overview: mixed, formatter: formatter)
        #expect(energy.isEstimated)
        #expect(!energy.isTodayEstimated)
        #expect(energy.todayText == "300 kcal")
        #expect(energy.totalText?.hasPrefix("≈") == true)
    }

    @Test func stepsSummaryOffersYesterdayAndAverageForTheMaxCard() {
        let summary = StepsTodaySummary(overview: overview, goal: 10_000, formatter: formatter)
        #expect(summary.yesterdayText == "6.000")
        #expect(summary.sevenDayAverageText == "4.000")
        PaceLocalization.$languageOverride.withValue(.english) {
            let english = StepsTodaySummary(overview: overview, goal: 10_000, formatter: ActivityFormatter(locale: Locale(identifier: "en_US"), calendar: Fixtures.activityCalendar))
            #expect(english.goalText == "of 10,000 steps")
            #expect(english.remainingText == "3,000 to go to your goal")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            let russian = StepsTodaySummary(overview: overview, goal: 10_000, formatter: formatter)
            #expect(russian.goalText == "из 10.000 шагов")
            #expect(russian.remainingText == "Ещё 3.000 до твоей цели")
        }
    }
}

// MARK: - Mitteilungen

struct HomeNotificationsTests {
    @Test func itemsComeOnlyFromRealSocialData() {
        let mia = SocialProfile(publicID: UUID(), username: "mia", displayName: "Mia")
        let ben = SocialProfile(publicID: UUID(), username: "ben", displayName: "Ben")
        let incoming = FriendRequest(id: UUID(), direction: .incoming, profile: mia, createdAt: Fixtures.date(2026, 10, 16, 8))
        let outgoing = FriendRequest(id: UUID(), direction: .outgoing, profile: ben, createdAt: Fixtures.date(2026, 10, 16, 9))
        let invitation = GroupInvitation(
            id: UUID(), groupID: UUID(), groupName: "Sonntagsrunde", groupKind: .friends, memberCount: 4,
            inviterUsername: "mia", inviterDisplayName: "Mia", createdAt: Fixtures.date(2026, 10, 15, 20)
        )
        let unread = ConversationSummary(
            id: UUID(), kind: .direct, title: "Leon", peer: nil, groupID: nil, groupImagePath: nil, memberCount: 2,
            lastMessage: nil, unreadCount: 3, canSend: true, updatedAt: Fixtures.date(2026, 10, 16, 10)
        )
        let read = ConversationSummary(
            id: UUID(), kind: .group, title: "Klasse 8b", peer: nil, groupID: UUID(), groupImagePath: nil, memberCount: 24,
            lastMessage: nil, unreadCount: 0, canSend: true, updatedAt: Fixtures.date(2026, 10, 16, 11)
        )

        let items = HomeNotifications.items(incomingRequests: [incoming, outgoing], invitations: [invitation], conversations: [unread, read])

        // Ausgehende Anfragen und gelesene Chats sind keine Mitteilungen; neueste zuerst.
        #expect(items.count == 3)
        #expect(items.map(\.date) == [Fixtures.date(2026, 10, 16, 10), Fixtures.date(2026, 10, 16, 8), Fixtures.date(2026, 10, 15, 20)])
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(items.map(\.message) == [
                "3 neue Nachrichten",
                "Mia möchte mit dir befreundet sein.",
                "Mia hat dich in „Sonntagsrunde“ eingeladen.",
            ])
            #expect(items[0].title == "Leon")
            #expect(HomeNotifications.bellAccessibilityLabel(count: 3) == "Mitteilungen, 3 neu")
            #expect(HomeNotifications.bellAccessibilityLabel(count: 0) == "Mitteilungen")
        }
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(items[1].message == "Mia wants to be your friend.")
            #expect(items[2].title == "Group invitation")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(items[0].message == "3 новых сообщения")
        }
        #expect(HomeNotifications.items(incomingRequests: [], invitations: [], conversations: [read]).isEmpty)
    }
}

// MARK: - Texte

struct HomeTextsTests {
    @Test func greetingAndHintsInAllLanguages() {
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(HomeTexts.greeting("Niklas") == "Hi Niklas")
            #expect(HomeTexts.editHint == "Halten und verschieben, um deine Übersicht anzupassen.")
            #expect(HomeTexts.chooseSize == "Größe auswählen")
            #expect(HomeTexts.rankingOffTitle == "Ranking ausgeschaltet")
        }
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(HomeTexts.greeting("Niklas") == "Hi Niklas")
            #expect(HomeTexts.addWidget == "Add widget")
            #expect(HomeTexts.done == "Done")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(HomeTexts.greeting("Niklas") == "Привет, Niklas")
            #expect(HomeTexts.greeting("") == "Привет")
            #expect(HomeTexts.customize == "Настроить")
        }
    }
}
