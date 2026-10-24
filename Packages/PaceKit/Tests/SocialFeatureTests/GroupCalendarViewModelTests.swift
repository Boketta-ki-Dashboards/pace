import Foundation
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import Testing

/// Gruppenkalender: Monatsraster ab Montag, ehrliche Zustände, Tagesbeste, Tagesrangliste und Navigation.
@MainActor
struct GroupCalendarViewModelTests {
    private let groupID = UUID(uuidString: "91000000-0000-4000-8000-000000000001")!
    private let leo = SocialProfile(publicID: UUID(uuidString: "91000000-0000-4000-8000-000000000011")!, username: "leo", displayName: "Leo")
    private let marie = SocialProfile(publicID: UUID(uuidString: "91000000-0000-4000-8000-000000000012")!, username: "marie", displayName: "Marie", nickname: "Mimi")
    private let me = SocialProfile(publicID: UUID(uuidString: "91000000-0000-4000-8000-000000000013")!, username: "niklas", displayName: "Niklas")

    /// Freitag, 16. Oktober 2026, 12 Uhr.
    private let now = Fixtures.date(2026, 10, 16, 12)

    private func entry(_ rank: Int, _ profile: SocialProfile, _ steps: Int, reached: Bool, isMe: Bool = false) -> GroupCalendarEntry {
        GroupCalendarEntry(rank: rank, profile: profile, competitionSteps: steps, reached: reached, isCurrentUser: isMe)
    }

    private func day(
        _ day: Int,
        month: Int = 10,
        reached: Int,
        members: Int = 3,
        hasData: Bool = true,
        isToday: Bool = false,
        ranking: [GroupCalendarEntry] = []
    ) -> GroupCalendarDay {
        let required = GroupStreakRules.requiredMembers(forMemberCount: members)
        return GroupCalendarDay(
            day: Fixtures.day(2026, month, day),
            dailyGoal: 8_000,
            memberCount: members,
            requiredCount: required,
            reachedCount: reached,
            secured: reached >= required,
            hasData: hasData,
            isToday: isToday,
            ranking: ranking
        )
    }

    /// Gruppe seit 28. September; 17. Oktober (morgen) und später gibt es noch nicht.
    private func makeCalendar(firstDay: LocalDate = Fixtures.day(2026, 9, 28)) -> GroupCalendar {
        var days: [GroupCalendarDay] = []
        var current = firstDay
        let calendar = Fixtures.activityCalendar
        while current <= Fixtures.day(2026, 10, 16) {
            switch (current.month, current.day) {
            case (10, 14):
                days.append(day(14, reached: 2, ranking: [
                    entry(1, leo, 14_320, reached: true),
                    entry(2, marie, 12_480, reached: true),
                    entry(3, me, 6_230, reached: false, isMe: true),
                ]))
            case (10, 15):
                days.append(day(15, reached: 0, hasData: false))
            case (10, 16):
                days.append(day(16, reached: 0, isToday: true, ranking: [
                    entry(1, me, 4_100, reached: false, isMe: true),
                    entry(2, leo, 2_000, reached: false),
                    entry(3, marie, 0, reached: false),
                ]))
            default:
                days.append(day(current.day, month: current.month, reached: 0, ranking: [
                    entry(1, marie, 7_900, reached: false),
                    entry(2, leo, 5_000, reached: false),
                    entry(3, me, 4_000, reached: false, isMe: true),
                ]))
            }
            current = calendar.adding(1, to: current)
        }
        return GroupCalendar(
            groupID: groupID,
            timeZone: "Europe/Berlin",
            groupToday: Fixtures.day(2026, 10, 16),
            firstGroupDay: firstDay,
            days: days
        )
    }

    private func make(_ calendar: GroupCalendar? = nil, error: SocialError? = nil) -> (GroupCalendarViewModel, SocialRepositoryStub) {
        let repository = SocialRepositoryStub { state in
            if let calendar { state.calendars[self.groupID] = calendar }
            state.error = error
        }
        let viewModel = GroupCalendarViewModel(
            groupID: groupID,
            groupName: "Smoking red",
            repository: repository,
            calendar: Fixtures.activityCalendar,
            now: { [now] in now }
        )
        return (viewModel, repository)
    }

    @Test func loadsTheMonthGridStartingOnMonday() async {
        let (viewModel, repository) = make(makeCalendar())

        await viewModel.load()

        let request = repository.state.withLock { $0.calendarRequests.first }
        // 1. Oktober 2026 ist ein Donnerstag: Raster von Montag, 28.9., bis Sonntag, 1.11.
        #expect(request?.1 == Fixtures.day(2026, 9, 28))
        #expect(request?.2 == Fixtures.day(2026, 11, 1))
        #expect(viewModel.state == .loaded)
        let weeks = viewModel.weeks
        #expect(weeks.count == 5)
        #expect(weeks.allSatisfy { $0.count == 7 })
        // Erste Woche: Mo–Mi gehören zum September (leer), dann 1.–4. Oktober.
        #expect(weeks[0].prefix(3).allSatisfy { $0 == nil })
        #expect(weeks[0][3]?.day == Fixtures.day(2026, 10, 1))
        #expect(viewModel.weekdays.count == 7)
    }

    @Test func cellsAreHonestAboutTheirState() async throws {
        let (viewModel, _) = make(makeCalendar())
        await viewModel.load()
        let cells = viewModel.weeks.joined().compactMap { $0 }
        func cell(_ day: Int) throws -> GroupCalendarViewModel.Cell {
            try #require(cells.first { $0.day == Fixtures.day(2026, 10, day) })
        }

        #expect(try cell(14).state == .secured)
        #expect(try cell(14).best?.profile == leo)
        #expect(try cell(15).state == .noData)
        #expect(try cell(15).best == nil)
        #expect(try cell(13).state == .missed)
        #expect(try cell(16).state == .open)
        #expect(try cell(16).isToday)
        #expect(try cell(17).state == .future)
        #expect(try !cell(17).isSelectable)
        #expect(try cell(17).best == nil)
    }

    @Test func todayIsSelectedAndAnyPastDayShowsItsFullRanking() async throws {
        let (viewModel, _) = make(makeCalendar())
        await viewModel.load()
        #expect(viewModel.selectedDay == Fixtures.day(2026, 10, 16))

        viewModel.select(Fixtures.day(2026, 10, 14))
        let selected = try #require(viewModel.selected)
        #expect(selected.ranking.map(\.shownName) == ["Leo", "Mimi", "Niklas"])
        #expect(selected.currentUserEntry?.competitionSteps == 6_230)

        let texts = PaceLocalization.$languageOverride.withValue(.german) {
            (viewModel.reachedText(selected), viewModel.requiredText(selected), viewModel.flameText(selected), viewModel.goalText(selected))
        }
        #expect(texts.0 == "2 von 3 Mitgliedern haben das Tagesziel erreicht.")
        #expect(texts.1.hasPrefix("Benötigt: 1"))
        #expect(texts.2 == "Flamme gesichert.")
        #expect(texts.3?.contains("pro Mitglied") == true)

        // Zukunft lässt sich nicht auswählen.
        viewModel.select(Fixtures.day(2026, 10, 20))
        #expect(viewModel.selectedDay == Fixtures.day(2026, 10, 14))
    }

    @Test func daysWithoutDataShowNoNumbers() async throws {
        let (viewModel, _) = make(makeCalendar())
        await viewModel.load()

        viewModel.select(Fixtures.day(2026, 10, 15))
        let state = try #require(viewModel.selectedState)
        #expect(state == .noData)
        #expect(viewModel.selected?.hasData == false)
        let text = PaceLocalization.$languageOverride.withValue(.german) { viewModel.emptyText(for: state) }
        #expect(text == "Keine Daten verfügbar.")
    }

    @Test func navigationStaysWithinTheGroupsLifetime() async {
        let (viewModel, repository) = make(makeCalendar())
        await viewModel.load()
        #expect(viewModel.canShowPrevious) // gegründet im September
        #expect(!viewModel.canShowNext)    // Oktober ist der laufende Monat
        #expect(!viewModel.canShowToday)

        await viewModel.showPrevious()
        #expect(viewModel.displayedMonth == Fixtures.day(2026, 9, 1))
        #expect(!viewModel.canShowPrevious)
        #expect(viewModel.canShowNext)
        #expect(viewModel.canShowToday)
        #expect(viewModel.selectedDay == Fixtures.day(2026, 9, 30))
        // Vor der Gründung: nicht auswählbar.
        let early = viewModel.weeks.joined().compactMap { $0 }.first { $0.day == Fixtures.day(2026, 9, 10) }
        #expect(early?.state == .beforeGroup)
        #expect(early?.isSelectable == false)

        await viewModel.showToday()
        #expect(viewModel.displayedMonth == Fixtures.day(2026, 10, 1))
        #expect(viewModel.selectedDay == Fixtures.day(2026, 10, 16))
        // Oktober kam aus dem Speicher – kein zweiter Abruf.
        #expect(repository.state.withLock { $0.calendarRequests.count } == 2)
    }

    @Test func reopeningRefreshesOldDataAndANewDayStartsOver() async {
        let clock = Locked(now)
        let repository = SocialRepositoryStub { $0.calendars[self.groupID] = self.makeCalendar() }
        let viewModel = GroupCalendarViewModel(
            groupID: groupID, groupName: "Smoking red", repository: repository,
            calendar: Fixtures.activityCalendar, now: { clock.withLock { $0 } }
        )
        await viewModel.appear()
        viewModel.select(Fixtures.day(2026, 10, 14))

        // Zwei Minuten später: Stand aus dem Speicher.
        clock.withLock { $0 = now.addingTimeInterval(120) }
        await viewModel.appear()
        #expect(repository.state.withLock { $0.calendarRequests.count } == 1)
        #expect(viewModel.selectedDay == Fixtures.day(2026, 10, 14))

        // Zehn Minuten später: neu geladen, Auswahl bleibt.
        clock.withLock { $0 = now.addingTimeInterval(600) }
        await viewModel.appear()
        #expect(repository.state.withLock { $0.calendarRequests.count } == 2)
        #expect(viewModel.selectedDay == Fixtures.day(2026, 10, 14))

        // Am nächsten Tag: neu im laufenden Monat, heute ausgewählt (der Server meldet den neuen Gruppentag).
        repository.state.withLock { state in
            let old = self.makeCalendar()
            state.calendars[self.groupID] = GroupCalendar(
                groupID: old.groupID, timeZone: old.timeZone, groupToday: Fixtures.day(2026, 10, 17),
                firstGroupDay: old.firstGroupDay,
                days: old.days + [self.day(17, reached: 0, isToday: true)]
            )
        }
        clock.withLock { $0 = Fixtures.date(2026, 10, 17, 8) }
        await viewModel.appear()
        #expect(repository.state.withLock { $0.calendarRequests.count } == 3)
        #expect(viewModel.today == Fixtures.day(2026, 10, 17))
        #expect(viewModel.selectedDay == Fixtures.day(2026, 10, 17))
    }

    @Test func missingServerSupportIsExplained() async {
        let (viewModel, _) = make(error: .unavailable)

        await viewModel.load()

        #expect(viewModel.state == .unavailable(SocialText.featureUnavailable))
    }

    @Test func loadingErrorsCanBeRetried() async {
        let (viewModel, repository) = make(makeCalendar(), error: .network)
        await viewModel.load()
        #expect(viewModel.state == .failed(SocialError.network.message))

        repository.state.withLock { $0.error = nil }
        await viewModel.load(force: true)
        #expect(viewModel.state == .loaded)
    }

    @Test func socialViewModelOffersTheCalendarOnlyForKnownGroups() async {
        let repository = SocialRepositoryStub { state in
            state.groups = [SocialRepositoryStub.group(id: self.groupID, name: "Smoking red")]
        }
        let social = SocialViewModel(repository: repository, ownUsername: { "niklas" }, calendar: Fixtures.activityCalendar, now: { [now] in now })
        await social.load()

        let calendar = social.groupCalendar(groupID: groupID)
        #expect(calendar?.groupName == "Smoking red")
        #expect(social.groupCalendar(groupID: groupID) === calendar)
        #expect(social.groupCalendar(groupID: UUID()) == nil)
    }
}
