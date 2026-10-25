import ActivityFeature
import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import Testing

/// Baut ein Dashboard mit Stubs; jeder Test bekommt eigene Instanzen.
@MainActor
private struct DashboardHarness {
    let dashboard: HomeDashboardViewModel
    let leaderboards: LeaderboardRepositoryStub
    let profiles: ProfileRepositoryStub
    let store: InMemoryHomePreferencesStore
    let log: OpenLog
    let health: HealthServiceStub

    init(
        participating: Bool = true,
        social: SocialRepositoryStub? = nil,
        chats: ChatRepositoryStub? = nil,
        preferences: HomePreferences? = nil
    ) async {
        let profile = Fixtures.profile(displayName: "Niklas", regionalLeaderboardEnabled: participating)
        let profiles = ProfileRepositoryStub { $0.profiles[profile.id] = profile }
        let profileStore = ProfileStore(profile: profile, profiles: profiles, regions: RegionRepositoryStub(), cache: InMemoryProfileCache())
        let leaderboards = LeaderboardRepositoryStub {
            $0.rankings[Fixtures.pfungstadt.id] = Fixtures.ranking(count: 20, currentUserRank: 12)
            $0.rankings[Fixtures.darmstadtDieburg.id] = Fixtures.ranking(count: 200, currentUserRank: 148)
            $0.rankings[Fixtures.hessen.id] = Fixtures.ranking(count: 300, currentUserRank: 241)
            $0.rankings[Fixtures.germany.id] = Fixtures.ranking(count: 2_000, currentUserRank: 1_852)
        }
        let now: @Sendable () -> Date = { Fixtures.date(2026, 10, 16, 9) }
        let health = HealthServiceStub {
            $0.setSteps(8_432, on: Fixtures.day(2026, 10, 16))
            $0.setSteps(6_000, on: Fixtures.day(2026, 10, 15))
            $0.hourlyTotals[.competitionSteps] = [
                Fixtures.day(2026, 10, 16): [7: 2_000, 8: 6_432],
                Fixtures.day(2026, 10, 15): [7: 1_000, 8: 2_000, 18: 3_000],
            ]
        }
        let activity = HomeViewModel(activityData: health, calendar: Fixtures.activityCalendar, now: now)
        let socialViewModel = SocialViewModel(
            repository: social,
            chats: chats.map { ChatListViewModel(repository: $0, media: nil, calendar: Fixtures.activityCalendar, now: now) },
            calendar: Fixtures.activityCalendar,
            now: now
        )
        let store = InMemoryHomePreferencesStore(preferences)
        let log = OpenLog()
        dashboard = HomeDashboardViewModel(
            activity: activity,
            standings: RegionalStandingsViewModel(
                store: profileStore,
                leaderboards: leaderboards,
                syncing: nil,
                calendar: Fixtures.activityCalendar,
                now: now
            ),
            settings: HomeSettings(store: store),
            streak: StepStreakTracker(
                history: ActivityHistoryStore(activityData: health, live: activity, calendar: Fixtures.activityCalendar, now: now),
                goals: StepGoalSettings(store: InMemoryStepGoalStore(), calendar: Fixtures.activityCalendar, now: now),
                recordStore: InMemoryStepStreakRecordStore(),
                calendar: Fixtures.activityCalendar,
                now: now
            ),
            social: socialViewModel,
            activityData: health,
            store: profileStore,
            calendar: Fixtures.activityCalendar,
            formatter: ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: Fixtures.activityCalendar),
            now: now,
            onOpenRankings: { log.rankings.append($0?.id) },
            onOpenSocial: { log.socialOpened += 1 }
        )
        self.leaderboards = leaderboards
        self.profiles = profiles
        self.store = store
        self.log = log
        self.health = health
        await activity.loadIfNeeded()
    }
}

@MainActor
private final class OpenLog {
    var rankings: [RegionID?] = []
    var socialOpened = 0
}

// MARK: - Anpassen-Modus

@MainActor
struct HomeEditModeTests {
    @Test func editModeRemovesWithUndoResizesAndMoves() async throws {
        let harness = await DashboardHarness()
        let dashboard = harness.dashboard
        #expect(!dashboard.isEditing)

        dashboard.beginEditing()
        #expect(dashboard.isEditing)

        let week = try #require(dashboard.modules.first { $0.kind == .week })
        dashboard.toggleSizeMenu(for: week.id)
        #expect(dashboard.sizeMenuModuleID == week.id)
        dashboard.setSize(.max, for: week.id)
        #expect(dashboard.sizeMenuModuleID == nil)
        #expect(dashboard.activeModuleID == week.id)
        #expect(dashboard.settings.module(id: week.id)?.size == .max)

        dashboard.remove(week.id)
        #expect(dashboard.lastRemoved?.module.id == week.id)
        #expect(!dashboard.modules.contains { $0.id == week.id })
        dashboard.undoRemove()
        #expect(dashboard.modules[2].id == week.id)
        #expect(dashboard.lastRemoved == nil)

        // „Deine Schritte heute“ bleibt Pflicht.
        let steps = try #require(dashboard.modules.first { $0.kind == .stepsToday })
        dashboard.remove(steps.id)
        #expect(dashboard.lastRemoved == nil)
        #expect(dashboard.modules.contains { $0.id == steps.id })

        // Ziehen: das gezogene Widget nimmt den Platz des Ziels ein.
        let streak = try #require(dashboard.modules.last)
        dashboard.draggingModuleID = streak.id
        dashboard.moveDragged(to: steps.id)
        #expect(dashboard.modules[1].id == streak.id)
        #expect(dashboard.activeModuleID == streak.id)
        // Abgelegt (oder abgebrochen): das Widget ist wieder normal, die neue Reihenfolge bleibt.
        dashboard.endDragging()
        #expect(dashboard.draggingModuleID == nil)
        #expect(dashboard.modules[1].id == streak.id)
        dashboard.moveDragged(to: steps.id)
        #expect(dashboard.modules[1].id == streak.id)
        dashboard.moveDown(streak.id)
        #expect(dashboard.modules[2].id == streak.id)
        dashboard.moveUp(streak.id)
        #expect(dashboard.modules[1].id == streak.id)

        // Alles ist sofort gespeichert – ein „Neustart“ sieht dasselbe Layout.
        #expect(HomeSettings(store: harness.store).modules == dashboard.modules)

        dashboard.remove(week.id)
        dashboard.endEditing()
        #expect(!dashboard.isEditing)
        #expect(dashboard.lastRemoved == nil)
        #expect(dashboard.activeModuleID == nil)
        #expect(dashboard.draggingModuleID == nil)
    }

    @Test func undoOffersExpireOnlyForTheSameRemoval() async throws {
        let harness = await DashboardHarness()
        let dashboard = harness.dashboard
        let week = try #require(dashboard.modules.first { $0.kind == .week })
        let friends = try #require(dashboard.modules.first { $0.kind == .friends })

        dashboard.remove(week.id)
        let first = try #require(dashboard.lastRemoved)
        dashboard.remove(friends.id)
        // Das Ausblenden des ersten Angebots lässt das zweite stehen.
        dashboard.dismissUndo(for: first)
        #expect(dashboard.lastRemoved?.module.id == friends.id)
    }
}

// MARK: - Ranking ausgeschaltet

@MainActor
struct HomeRankingVisibilityTests {
    @Test func rankingOffLoadsNoRankingDataAndShowsNeutralCards() async throws {
        let harness = await DashboardHarness(participating: false)
        let dashboard = harness.dashboard

        await dashboard.loadIfNeeded()
        await dashboard.stepsDidChange()
        await dashboard.refresh()

        #expect(!dashboard.isRankingVisible)
        #expect(harness.leaderboards.state.current.neighborhoodRequests.isEmpty)
        #expect(harness.leaderboards.state.current.pageRequests.isEmpty)
        let ranks = try #require(dashboard.modules.first { $0.kind == .regionRanks })
        #expect(dashboard.regionCards(for: ranks).allSatisfy { $0.rank == nil && $0.stepsToNextPlace == nil })
    }

    @Test func enablingVisibilityIsSavedAndLoadsRankings() async throws {
        let harness = await DashboardHarness(participating: false)
        let dashboard = harness.dashboard
        await dashboard.loadIfNeeded()

        dashboard.requestRankingVisibility()
        #expect(dashboard.isConfirmingRankingVisibility)
        await dashboard.enableRankingVisibility()

        #expect(!dashboard.isConfirmingRankingVisibility)
        #expect(dashboard.isRankingVisible)
        #expect(harness.profiles.state.current.profiles[Fixtures.userID]?.regionalLeaderboardEnabled == true)
        #expect(!harness.leaderboards.state.current.neighborhoodRequests.isEmpty)
        let ranks = try #require(dashboard.modules.first { $0.kind == .regionRanks })
        #expect(dashboard.regionCards(for: ranks).map(\.rank) == [12, 148, 241, 1_852])

        // Bereits sichtbar: keine erneute Nachfrage.
        dashboard.requestRankingVisibility()
        #expect(!dashboard.isConfirmingRankingVisibility)
    }
}

// MARK: - Mitteilungen und Navigation

@MainActor
struct HomeNotificationAndNavigationTests {
    private static let klasse = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!

    private func socialStub() -> SocialRepositoryStub {
        SocialRepositoryStub { state in
            let mia = SocialProfile(publicID: UUID(), username: "mia", displayName: "Mia")
            state.requests = [
                FriendRequest(id: UUID(), direction: .incoming, profile: mia, createdAt: Fixtures.date(2026, 10, 16, 8)),
                FriendRequest(id: UUID(), direction: .outgoing, profile: mia, createdAt: Fixtures.date(2026, 10, 16, 7)),
            ]
            state.invitations = [GroupInvitation(
                id: UUID(), groupID: UUID(), groupName: "Sonntagsrunde", groupKind: .friends, memberCount: 4,
                inviterUsername: "mia", inviterDisplayName: "Mia", createdAt: Fixtures.date(2026, 10, 15, 20)
            )]
            state.groups = [SocialRepositoryStub.group(id: Self.klasse, name: "Klasse 8b")]
        }
    }

    private func chatStub() -> ChatRepositoryStub {
        ChatRepositoryStub { state in
            state.conversations = [
                ConversationSummary(
                    id: UUID(), kind: .direct, title: "Leon", peer: nil, groupID: nil, groupImagePath: nil, memberCount: 2,
                    lastMessage: nil, unreadCount: 2, canSend: true, updatedAt: Fixtures.date(2026, 10, 16, 10)
                ),
                ConversationSummary(
                    id: UUID(), kind: .group, title: "Klasse 8b", peer: nil, groupID: Self.klasse, groupImagePath: nil, memberCount: 6,
                    lastMessage: nil, unreadCount: 0, canSend: true, updatedAt: Fixtures.date(2026, 10, 16, 11)
                ),
            ]
        }
    }

    @Test func notificationsComeFromRealSocialAndChatData() async {
        let harness = await DashboardHarness(social: socialStub(), chats: chatStub())
        let dashboard = harness.dashboard
        #expect(dashboard.notificationCount == 0)

        await dashboard.loadNotificationsIfNeeded()

        #expect(dashboard.areNotificationsAvailable)
        #expect(dashboard.notificationCount == 3)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(dashboard.notifications.map(\.message) == [
                "2 neue Nachrichten",
                "Mia möchte mit dir befreundet sein.",
                "Mia hat dich in „Sonntagsrunde“ eingeladen.",
            ])
        }
        dashboard.open(dashboard.notifications[0])
        #expect(harness.log.socialOpened == 1)
    }

    @Test func withoutSocialBackendThereAreNoNotifications() async {
        let harness = await DashboardHarness()
        await harness.dashboard.loadNotificationsIfNeeded()
        #expect(!harness.dashboard.areNotificationsAvailable)
        #expect(harness.dashboard.notifications.isEmpty)
    }

    @Test func groupWidgetOpensTheRealGroup() async throws {
        let harness = await DashboardHarness(social: socialStub())
        let dashboard = harness.dashboard
        await dashboard.social.load()
        let module = try #require(dashboard.settings.add(HomeModule(kind: .groups, configuration: HomeWidgetConfiguration(groupID: Self.klasse))))

        guard case .single(let group) = dashboard.groupSelection(for: module) else {
            Issue.record("Gruppe nicht gefunden")
            return
        }
        dashboard.openGroup(group.id)
        #expect(dashboard.social.requestedGroup == Self.klasse)
        #expect(harness.log.socialOpened == 1)

        // Eine Gruppe, die es nicht mehr gibt, zeigt einen Hinweis.
        let gone = try #require(dashboard.settings.add(HomeModule(kind: .groups, configuration: HomeWidgetConfiguration(groupID: UUID()))))
        #expect(dashboard.groupSelection(for: gone) == .missing)
    }

    @Test func calendarAndGalleryAreCreatedFromTheDashboard() async throws {
        let harness = await DashboardHarness()
        let dashboard = harness.dashboard

        let calendar = dashboard.calendar(for: CalendarRoute())
        #expect(calendar.route == CalendarRoute())

        let add = dashboard.gallery(for: HomeWidgetGalleryRoute())
        #expect(add.mode == .add)
        let week = try #require(dashboard.modules.first { $0.kind == .week })
        let edit = dashboard.gallery(for: HomeWidgetGalleryRoute(editingID: week.id))
        #expect(edit.mode == .edit(week.id))
        #expect(edit.kind == .week)
    }

    @Test func calendarWidgetUsesTodaysLiveSteps() async throws {
        let harness = await DashboardHarness()
        let widget = harness.dashboard.calendarWidget(size: .small)
        let today = try #require(widget.weeks.first?.first { $0.isToday })
        #expect(today.steps == 8_432)
        #expect(today.state == .notReached)
        #expect(widget.weeks.first?.last?.state == .future)
    }

    @Test func greetingFollowsTheLanguage() async {
        let harness = await DashboardHarness()
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(harness.dashboard.greeting == "Привет, Niklas")
        }
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(harness.dashboard.greeting == "Hi Niklas")
        }
    }
}

// MARK: - Widget-Galerie

@MainActor
struct HomeWidgetGalleryTests {
    private static let leon = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
    private static let marie = UUID(uuidString: "40000000-0000-4000-8000-000000000002")!
    private static let gotscha = UUID(uuidString: "40000000-0000-4000-8000-000000000003")!
    private static let tim = UUID(uuidString: "40000000-0000-4000-8000-000000000004")!
    private static let klasse = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!

    private func socialStub() -> SocialRepositoryStub {
        SocialRepositoryStub { state in
            let names = [(Self.leon, "Leon"), (Self.marie, "Marie"), (Self.gotscha, "Gotscha"), (Self.tim, "Tim")]
            state.friends = names.map { Friend(profile: SocialProfile(publicID: $0.0, username: $0.1.lowercased(), displayName: $0.1), friendsSince: .distantPast) }
            state.ranking = [
                LeaderboardEntry(rank: 1, publicUserID: Self.leon, username: "leon", displayName: "Leon", competitionSteps: 12_480, isCurrentUser: false),
                LeaderboardEntry(rank: 2, publicUserID: Self.marie, username: "marie", displayName: "Marie", competitionSteps: 10_920, isCurrentUser: false),
                LeaderboardEntry(rank: 3, publicUserID: Fixtures.publicUserID, username: "niklas", displayName: "Niklas", competitionSteps: 8_432, isCurrentUser: true),
                LeaderboardEntry(rank: 4, publicUserID: Self.gotscha, username: "gotscha", displayName: "Gotscha", competitionSteps: 7_921, isCurrentUser: false),
            ]
            state.groups = [SocialRepositoryStub.group(id: Self.klasse, name: "Klasse 8b")]
        }
    }

    @Test func friendsWidgetsAreConfiguredAndAddedIndependently() async throws {
        let harness = await DashboardHarness(social: socialStub())
        let dashboard = harness.dashboard
        let gallery = dashboard.gallery(for: HomeWidgetGalleryRoute())
        await gallery.loadIfNeeded()

        gallery.select(.friends)
        #expect(gallery.kind == .friends)
        // Chips: ausgewählte zuerst, dann nach heutigem Ranking; Tim (ohne Ranking) steht in der vollen Liste.
        #expect(gallery.friendChoices.map(\.displayName) == ["Leon", "Marie", "Gotscha", "Tim"])
        gallery.toggleFriend(Self.gotscha)
        #expect(gallery.chipFriends.map(\.displayName) == ["Gotscha", "Leon", "Marie"])
        gallery.toggleFriend(Self.leon)
        gallery.toggleFriend(Self.marie)
        gallery.toggleFriend(Self.gotscha)
        #expect(gallery.chipFriends.map(\.displayName) == ["Leon", "Marie", "Gotscha"])
        #expect(gallery.isSelected(friend: Self.leon))
        #expect(!gallery.isSelected(friend: Self.gotscha))
        gallery.toggleFriend(Self.tim)
        gallery.toggleFriend(Self.gotscha)
        // Vier Ausgewählte, drei Chips: einer steht unter „Weitere…“.
        #expect(gallery.chipFriends.map(\.displayName) == ["Leon", "Marie", "Tim"])
        #expect(gallery.additionalSelectedCount == 1)
        gallery.toggleFriend(Self.tim)
        gallery.toggleFriend(Self.gotscha)

        gallery.name = "  Meine   Laufrunde "
        gallery.size = .medium
        // Die Vorschau ist das echte Widget mit echten Daten.
        #expect(gallery.draft.title == "Meine Laufrunde")
        let preview = dashboard.friendsWidget(for: gallery.draft)
        #expect(preview.rows(for: .medium).map(\.entry.displayName) == ["Leon", "Marie", "Niklas"])
        #expect(gallery.canSave)
        #expect(gallery.save())

        // Ein zweites Freunde-Widget mit eigener Auswahl.
        let second = dashboard.gallery(for: HomeWidgetGalleryRoute())
        second.select(.friends)
        second.toggleFriend(Self.gotscha)
        second.name = "Arbeitskollegen"
        second.size = .small
        #expect(second.save())

        let friendsWidgets = dashboard.modules.filter { $0.kind == .friends }
        #expect(friendsWidgets.count == 3)
        #expect(friendsWidgets[1].title == "Meine Laufrunde")
        #expect(friendsWidgets[1].configuration.friendIDs == [Self.leon, Self.marie])
        #expect(friendsWidgets[2].title == "Arbeitskollegen")
        #expect(friendsWidgets[2].size == .small)
        #expect(HomeSettings(store: harness.store).modules == dashboard.modules)
    }

    @Test func editingChangesOnlyTheChosenWidget() async throws {
        let harness = await DashboardHarness(social: socialStub())
        let dashboard = harness.dashboard
        let neighborhood = try #require(dashboard.modules.first { $0.kind == .neighborhood })
        await dashboard.loadIfNeeded()

        let gallery = dashboard.gallery(for: HomeWidgetGalleryRoute(editingID: neighborhood.id))
        #expect(gallery.isEditing)
        #expect(gallery.kind == .neighborhood)
        #expect(!gallery.isSelectable(.friends))
        gallery.select(.friends)
        #expect(gallery.kind == .neighborhood)
        #expect(gallery.levelChoices == [.municipality, .district, .state, .country])
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(gallery.levelTitle(.district) == "Darmstadt-Dieburg")
            #expect(gallery.title == "Widget bearbeiten")
            #expect(gallery.saveTitle == "Änderungen sichern")
        }
        gallery.toggleLevel(.state)
        gallery.size = .max
        #expect(gallery.save())

        let edited = try #require(dashboard.settings.module(id: neighborhood.id))
        #expect(edited.regionLevel == .state)
        #expect(edited.size == .max)
        #expect(dashboard.modules[3].id == neighborhood.id)
    }

    @Test func stepsCardIsEditedUnderStepsAndActivity() async throws {
        let harness = await DashboardHarness()
        let steps = try #require(harness.dashboard.modules.first { $0.kind == .stepsToday })
        let gallery = harness.dashboard.gallery(for: HomeWidgetGalleryRoute(editingID: steps.id))

        #expect(gallery.selectedCategory == .activity)
        // Auftrag 5: Die Schrittkarte gibt es in allen vier Größen; „Klein“ zeigt nur Zahl, Prozent und Balken.
        #expect(gallery.supportedSizes == [.small, .medium, .large, .max])
        gallery.size = .small
        #expect(gallery.draft.size == .small)
        #expect(gallery.draft.shownDetails.isEmpty)
        gallery.size = .max
        #expect(gallery.draft.shownDetails == [.distanceEnergy, .floorsExercise, .weekChart, .comparison])
    }

    @Test func singleWidgetsAndDuplicatesAreExplained() async throws {
        let harness = await DashboardHarness(social: socialStub())
        let gallery = harness.dashboard.gallery(for: HomeWidgetGalleryRoute())

        #expect(gallery.isAlreadyOnHome(.week))
        #expect(!gallery.isAlreadyOnHome(.calendar))
        gallery.select(.week)
        #expect(!gallery.canSave)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(gallery.validationMessage == "„Deine Woche“ zeigt das schon auf deiner Übersicht.")
        }
        #expect(!gallery.save())

        gallery.select(.calendar)
        gallery.size = .large
        #expect(gallery.save())
        #expect(harness.dashboard.modules.last?.kind == .calendar)
        #expect(harness.dashboard.modules.last?.size == .large)
    }

    @Test func groupAndRegionalAndActivityChoices() async throws {
        let harness = await DashboardHarness(social: socialStub())
        let dashboard = harness.dashboard
        let gallery = dashboard.gallery(for: HomeWidgetGalleryRoute())
        await gallery.loadIfNeeded()

        gallery.select(.groups)
        #expect(gallery.groups.map(\.name) == ["Klasse 8b"])
        // „Alle Gruppen“ gibt es schon.
        #expect(!gallery.canSave)
        gallery.groupID = Self.klasse
        #expect(gallery.canSave)

        gallery.select(.regionRanks)
        gallery.toggleLevel(.district)
        gallery.toggleLevel(.state)
        #expect(gallery.regionLevels == [.municipality, .country])
        gallery.toggleLevel(.municipality)
        gallery.toggleLevel(.country)
        // Mindestens eine Ebene bleibt.
        #expect(gallery.regionLevels == [.country])
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(gallery.levelTitle(.municipality) == "Stadt")
        }
        #expect(gallery.save())
        #expect(dashboard.modules.last?.regionLevels == [.country])

        let activity = dashboard.gallery(for: HomeWidgetGalleryRoute())
        activity.select(.activity)
        activity.metric = .activeEnergy
        activity.size = .large
        #expect(activity.save())
        #expect(dashboard.modules.last?.metric == .activeEnergy)
        #expect(dashboard.activityWidget(for: try #require(dashboard.modules.last))?.metric == .activeEnergy)
    }

    @Test func widgetContentsAreChosenPerWidgetAndFitTheSize() async throws {
        let harness = await DashboardHarness(social: socialStub())
        let dashboard = harness.dashboard
        let streak = try #require(dashboard.modules.first { $0.kind == .streak })
        let gallery = dashboard.gallery(for: HomeWidgetGalleryRoute(editingID: streak.id))
        // Ausgangspunkt ist der Standard der Größe „Mittel“: der Rekord.
        #expect(gallery.detailChoices == [.record, .week, .milestone, .recentDays])
        #expect(gallery.isSelected(detail: .record))
        #expect(!gallery.isSelected(detail: .milestone))
        gallery.toggleDetail(.milestone)
        #expect(gallery.draft.shownDetails == [.record, .milestone])
        gallery.toggleDetail(.week)
        // „Mittel“ zeigt höchstens zwei – in fester Reihenfolge, der Hinweis sagt es.
        #expect(gallery.draft.shownDetails == [.record, .week])
        #expect(gallery.detailsHint != nil)
        gallery.size = .max
        #expect(gallery.draft.shownDetails == [.record, .week, .milestone])
        gallery.name = "Meine Flamme"
        #expect(gallery.save())
        let saved = try #require(dashboard.settings.module(id: streak.id))
        #expect(saved.configuration.details == [.record, .week, .milestone])
        #expect(dashboard.title(for: saved) == "Meine Flamme")

        // Entspricht die Auswahl dem Standard der Größe, wird nichts gespeichert: Das Widget folgt weiter der Größe.
        let again = dashboard.gallery(for: HomeWidgetGalleryRoute(editingID: streak.id))
        again.toggleDetail(.milestone)
        again.toggleDetail(.recentDays)
        #expect(again.save())
        #expect(dashboard.settings.module(id: streak.id)?.configuration.details == nil)
    }

    @Test func groupContentsNeedAChosenGroupAndSmallShowsOnlyTheEssentials() async {
        let harness = await DashboardHarness(social: socialStub())
        let gallery = harness.dashboard.gallery(for: HomeWidgetGalleryRoute())
        await gallery.loadIfNeeded()
        gallery.select(.groups)
        #expect(gallery.detailChoices.isEmpty)
        gallery.groupID = Self.klasse
        #expect(gallery.detailChoices == [.groupProgress, .groupGoal, .groupMembers])
        gallery.size = .small
        #expect(gallery.draft.shownDetails.isEmpty)
        #expect(gallery.detailsHint != nil)

        gallery.select(.friends)
        gallery.size = .medium
        #expect(!gallery.isAvailable(.friendChart))
        #expect(gallery.isAvailable(.friendGap))
        #expect(gallery.detailsHint != nil)
        // Neue Kategorie: Standard-Inhalte, keine aus der vorherigen Auswahl.
        #expect(gallery.draft.configuration.details == nil)
    }

    @Test func dayBestComesFromRealStepsOnly() async throws {
        let harness = await DashboardHarness()
        await harness.dashboard.streak.loadIfNeeded()
        let best = try #require(harness.dashboard.dayBest)
        #expect(best.steps == 8_432)
        #expect(best.isToday)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(best.title == "Tagesbestwert · Heute")
        }
    }
}

/// Vier regionale Karten zuverlässig (Auftrag 5, A3): Standard, Speichern, Migration, Größe, Bearbeiten, Neustart und
/// fehlende Daten – ohne eigene Auswahl zeigt das Widget immer alle vier Ebenen.
@MainActor
struct RegionCardsReliabilityTests {
    private func regionWidget(in modules: [HomeModule]) throws -> HomeModule {
        try #require(modules.first { $0.kind == .regionRanks })
    }

    @Test func theDefaultWidgetShowsAllFourLevelsAndStoresNoSelection() throws {
        let module = try regionWidget(in: HomePreferences.defaultModules())
        #expect(module.regionLevels == RegionLevel.allCases)
        #expect(module.configuration.regionLevels == nil)
        let json = String(decoding: try JSONEncoder().encode(module), as: UTF8.self)
        #expect(!json.contains("levels"))
    }

    @Test func storingAndReloadingKeepsFourLevels() throws {
        let suite = "pace.tests.regioncards.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = UserDefaultsHomePreferencesStore(suiteName: suite)
        let settings = HomeSettings(store: store)
        let id = try regionWidget(in: settings.modules).id
        settings.setSize(.large, for: id)
        settings.setSize(.max, for: id)
        settings.setSize(.small, for: id)
        settings.move(id, toIndex: 3)

        // „Neustart“: neue Einstellungen aus demselben Speicher.
        let reloaded = HomeSettings(store: UserDefaultsHomePreferencesStore(suiteName: suite))
        let module = try #require(reloaded.module(id: id))
        #expect(module.size == .small)
        #expect(module.regionLevels == RegionLevel.allCases)
    }

    @Test func storedSelectionsAreRepairedNotShrunk() throws {
        func decodeLevels(_ levels: String) throws -> [RegionLevel] {
            let json = #"{"version":3,"modules":[{"id":"r","kind":"regionRanks","size":"medium","config":{"levels":"# + levels + #"}}]}"#
            let preferences = try JSONDecoder().decode(HomePreferences.self, from: Data(json.utf8)).normalized()
            return try regionWidget(in: preferences.modules).regionLevels
        }
        // Leer, unbekannt oder alle vier: immer alle vier (gespeichert wird dann nichts).
        #expect(try decodeLevels("[]") == RegionLevel.allCases)
        #expect(try decodeLevels(#"["galaxy"]"#) == RegionLevel.allCases)
        #expect(try decodeLevels(#"["country","state","district","municipality"]"#) == RegionLevel.allCases)
        // Doppelt oder ungeordnet: bereinigt, in fester Reihenfolge.
        #expect(try decodeLevels(#"["state","municipality","state"]"#) == [.municipality, .state])
    }

    @Test func versionOneMigrationKeepsFourLevels() throws {
        let json = #"{"sections":[{"section":"regionRanks","isVisible":true},{"section":"stepsToday","isVisible":true}]}"#
        let preferences = try JSONDecoder().decode(HomePreferences.self, from: Data(json.utf8))
        #expect(try regionWidget(in: preferences.modules).regionLevels == RegionLevel.allCases)
    }

    @Test(arguments: [nil, Fixtures.pfungstadtHierarchy, Fixtures.frankfurtHierarchy, Fixtures.berlinHierarchy])
    func cardsAlwaysCoverAllFourLevels(hierarchy: RegionHierarchy?) {
        // Vor dem Laden, ohne Platzierungen, bei kreisfreier Stadt und Stadtstaat: vier Karten.
        let cards = HomeRegionCards.cards(hierarchy: hierarchy, standings: nil)
        #expect(cards.map(\.level) == RegionLevel.allCases)
    }

    @Test func missingMunicipalityCountsStillGiveFourCards() {
        // Unvollständige Gebietsdaten (z. B. Zähler 0) dürfen keine Karte entfallen lassen.
        let district = Region(id: "DE:06432", code: "06432", name: "Darmstadt-Dieburg", level: .district, kind: .landkreis, parentID: "DE:06", municipalityCount: 0)
        let hierarchy = RegionHierarchy(municipality: Fixtures.pfungstadt, district: district, state: Fixtures.hessen, country: Fixtures.germany)
        let cards = HomeRegionCards.cards(hierarchy: hierarchy, standings: nil)
        #expect(cards.count == 4)
        #expect(cards.map(\.name) == ["Pfungstadt", "Darmstadt-Dieburg", "Hessen", "Deutschland"])
    }

    @Test func editingSizeOrNameKeepsAllFourLevels() async throws {
        let harness = await DashboardHarness()
        let id = try regionWidget(in: harness.dashboard.modules).id
        let gallery = harness.dashboard.gallery(for: HomeWidgetGalleryRoute(editingID: id))
        #expect(gallery.regionLevels == RegionLevel.allCases)
        #expect(!gallery.hidesLevels)
        gallery.size = .max
        gallery.name = "Meine Region"
        #expect(gallery.save())
        let saved = try #require(HomeSettings(store: harness.store).module(id: id))
        #expect(saved.regionLevels == RegionLevel.allCases)
        #expect(saved.configuration.regionLevels == nil)
        #expect(harness.dashboard.regionCards(for: saved).count == 4)
    }

    @Test func theEditorSaysHowManyLevelsAreShownAndRestoresAllFour() async throws {
        let harness = await DashboardHarness()
        let id = try regionWidget(in: harness.dashboard.modules).id
        let gallery = harness.dashboard.gallery(for: HomeWidgetGalleryRoute(editingID: id))
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(gallery.levelSummary == "4 von 4 Ebenen sichtbar")
            #expect(gallery.levelChoices.map(gallery.levelTitle) == ["Stadt", "Landkreis", "Bundesland", "Land"])
            gallery.toggleLevel(.country)
            #expect(gallery.levelSummary == "3 von 4 Ebenen sichtbar")
            #expect(gallery.hidesLevels)
            #expect(gallery.draft.regionLevels == [.municipality, .district, .state])
            gallery.showAllLevels()
            #expect(gallery.levelSummary == "4 von 4 Ebenen sichtbar")
        }
        // Mindestens eine Ebene bleibt.
        for level in RegionLevel.allCases { gallery.toggleLevel(level) }
        #expect(gallery.regionLevels.count == 1)
    }

    @Test func aSecondRegionWidgetPointsToTheSizeInsteadOfHidingLevels() async throws {
        let harness = await DashboardHarness()
        let gallery = harness.dashboard.gallery(for: HomeWidgetGalleryRoute())
        gallery.select(.regionRanks)
        gallery.size = .max
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(gallery.validationMessage?.contains("Größe") == true)
        }
        #expect(!gallery.canSave)
    }
}

/// Stundenwerte für Tagesvergleich und Aktivitätszeiten (Auftrag 5, D): eine Abfrage für beide Widgets, keine
/// Wiederholung ohne neuen HealthKit-Stand, gestern nur einmal pro Tag.
@MainActor
struct InsightWidgetLoadingTests {
    private func hourlyRequests(_ harness: DashboardHarness) -> [LocalDate] {
        harness.health.recordedCalls.hourlyTotalsRequests.map(\.1)
    }

    @Test func hourlyValuesAreLoadedOnceForBothWidgets() async throws {
        let harness = await DashboardHarness()
        let dashboard = harness.dashboard
        // Ohne passendes Widget wird nichts abgefragt.
        await dashboard.loadHourlyIfNeeded()
        #expect(hourlyRequests(harness).isEmpty)

        _ = dashboard.settings.add(.dayComparison)
        _ = dashboard.settings.add(.activityTimes)
        await dashboard.loadHourlyIfNeeded()
        #expect(hourlyRequests(harness) == [Fixtures.day(2026, 10, 16), Fixtures.day(2026, 10, 15)])
        // Erneut ohne neuen HealthKit-Stand: keine weitere Abfrage.
        await dashboard.loadHourlyIfNeeded()
        await dashboard.loadHourlyIfNeeded()
        #expect(hourlyRequests(harness).count == 2)

        // Tagesvergleich bis 9:00: gestern 1.000 + 2.000 = 3.000, heute 8.432.
        let comparison = try #require(dashboard.dayComparisonWidget)
        #expect(comparison.yesterdaySteps == 3_000)
        #expect(comparison.todaySteps == 8_432)
        #expect(comparison.yesterdayTotal == 6_000)
        let times = try #require(dashboard.activityTimesWidget)
        #expect(times.totalSteps == 8_432)
        #expect(times.peak?.id == "morning")

        // Neuer HealthKit-Stand: nur heute neu, gestern aus dem Speicher.
        harness.health.update { $0.setSteps(8_900, on: Fixtures.day(2026, 10, 16)) }
        await dashboard.activity.refresh(trigger: .healthKitUpdate)
        await dashboard.loadHourlyIfNeeded()
        #expect(hourlyRequests(harness) == [Fixtures.day(2026, 10, 16), Fixtures.day(2026, 10, 15), Fixtures.day(2026, 10, 16)])
    }

    /// Produkt-Review Auftrag 5: Vor dem Laden „Laden“ statt „keine Werte“, nach einem Fehler ein Hinweis; erneut
    /// versucht wird mit Pull-to-Refresh.
    @Test func hourlyWidgetsShowLoadingAndFailureInsteadOfEmptyStates() async throws {
        let harness = await DashboardHarness()
        let dashboard = harness.dashboard
        _ = dashboard.settings.add(.dayComparison)
        _ = dashboard.settings.add(.activityTimes)
        await dashboard.activity.loadIfNeeded()
        // Tageswerte da, Stundenwerte noch nicht: kein Widget-Inhalt (Laden), kein Hinweis.
        #expect(dashboard.dayComparisonWidget == nil)
        #expect(dashboard.activityTimesWidget == nil)
        #expect(dashboard.hourlyUnavailableText == nil)

        harness.health.update { $0.dailyTotalsError = .queryFailed(reason: "offline") }
        await dashboard.loadHourlyIfNeeded()
        #expect(dashboard.hourlyFailed)
        #expect(dashboard.dayComparisonWidget == nil)
        #expect(dashboard.activityTimesWidget == nil)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(dashboard.hourlyUnavailableText == "Stundenwerte gerade nicht verfügbar. Zum Aktualisieren nach unten ziehen.")
        }

        harness.health.update { $0.dailyTotalsError = nil }
        await dashboard.refresh()
        #expect(!dashboard.hourlyFailed)
        #expect(dashboard.hourlyUnavailableText == nil)
        #expect(dashboard.dayComparisonWidget?.isAvailable == true)
        #expect(dashboard.activityTimesWidget?.totalSteps == 8_432)
    }

    @Test func groupProgressAndRecordsUseLoadedData() async throws {
        let harness = await DashboardHarness()
        let dashboard = harness.dashboard
        _ = dashboard.settings.add(.records)
        _ = dashboard.settings.add(.streakWeek)
        #expect(dashboard.showsStreak)
        await dashboard.loadStreakIfNeeded()
        let records = try #require(dashboard.settings.modules.first { $0.kind == .records })
        let widget = try #require(dashboard.recordsWidget(for: records))
        #expect(widget.selected == .bestDay)
        #expect(widget.primary?.value == "8.432 Schritte")
        #expect(dashboard.streakWidget?.week.count == 7)

        let group = HomeModule(kind: .groupProgress, configuration: HomeWidgetConfiguration(groupID: UUID()))
        for module in dashboard.settings.modules where module.kind == .friends || module.kind == .groups {
            _ = dashboard.settings.remove(module.id)
        }
        #expect(!dashboard.showsSocial)
        _ = dashboard.settings.add(group)
        // Das Widget braucht die Gruppen (ohne eigene Abfrage, über das geteilte Social-ViewModel).
        #expect(dashboard.showsSocial)
        // Ohne Social-Backend: ehrlicher Hinweis – weder endloses Laden noch „gelöscht“.
        guard case .unavailable(let message) = dashboard.groupProgressWidget(for: group) else {
            Issue.record("Hinweis erwartet")
            return
        }
        #expect(!message.isEmpty)
    }
}

/// Galerie für den Gruppenfortschritt (Auftrag 5): erste Gruppe als Vorschlag, Pflichtauswahl, kein Übertrag zu „Gruppen“.
@MainActor
struct GroupProgressGalleryTests {
    @Test func aGroupIsSuggestedAndRequired() async throws {
        let social = SocialRepositoryStub { state in
            state.groups = [
                SocialRepositoryStub.group(id: UUID(uuidString: "70000000-0000-4000-8000-000000000001")!, name: "Laufteam"),
                SocialRepositoryStub.group(id: UUID(uuidString: "70000000-0000-4000-8000-000000000002")!, name: "Klasse 8b"),
            ]
        }
        let harness = await DashboardHarness(social: social)
        await harness.dashboard.social.load()
        let gallery = harness.dashboard.gallery(for: HomeWidgetGalleryRoute())
        gallery.select(.groupProgress)
        #expect(gallery.groupID == harness.dashboard.social.groups.first?.id)
        #expect(gallery.canSave)
        // Zu „Gruppen“ gewechselt: der bloße Vorschlag gilt nicht – dort weiter „Alle Gruppen“.
        gallery.select(.groups)
        #expect(gallery.groupID == nil)
        // Selbst gewählt bleibt gewählt.
        gallery.select(.groupProgress)
        let second = try #require(harness.dashboard.social.groups.last?.id)
        gallery.groupID = second
        gallery.select(.groups)
        #expect(gallery.groupID == second)
        // Ohne Gruppe lässt sich der Gruppenfortschritt nicht sichern.
        gallery.select(.groupProgress)
        gallery.groupID = nil
        #expect(!gallery.canSave)
    }
}
