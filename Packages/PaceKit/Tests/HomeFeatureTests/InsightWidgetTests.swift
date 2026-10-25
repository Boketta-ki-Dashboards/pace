import ActivityFeature
import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
import SocialFeature
import Testing

/// Die fünf neuen Widgets (Auftrag 5, Teil D): nur echte Werte, ehrliche Leerzustände, Speichern.
struct InsightWidgetTests {
    private let formatter = ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: Fixtures.activityCalendar)

    // MARK: Tagesvergleich

    @Test func dayComparisonUsesYesterdayUpToTheSameTime() {
        let yesterday: [Int: Double] = [7: 500, 8: 900, 12: 1_100, 17: 1_800]
        let widget = HomeDayComparisonWidget(
            todaySteps: 2_600, yesterdayHourly: yesterday, yesterdayTotal: 4_300,
            currentHour: 12, fractionOfCurrentHour: 0.5, timeText: "bis 12:30", formatter: formatter
        )
        // 500 + 900 + 1.100 × 0,5 = 1.950 – nicht der ganze Tag (4.300).
        #expect(widget.yesterdaySteps == 1_950)
        #expect(widget.direction == .ahead)
        #expect(widget.differenceText == "+650")
        #expect(widget.percentText == "+33 %")
        #expect(widget.yesterdayTotalText == "4.300")
        #expect(widget.todayLevel == 1)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(widget.headline == "650 mehr als gestern um diese Zeit")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(widget.headline == "На 650 больше, чем вчера в это время")
        }
    }

    @Test func withoutYesterdaysHourlyValuesThereIsNoComparison() {
        for hourly in [nil, [:]] as [[Int: Double]?] {
            let widget = HomeDayComparisonWidget(
                todaySteps: 3_000, yesterdayHourly: hourly, yesterdayTotal: 5_000,
                currentHour: 15, fractionOfCurrentHour: 0, timeText: "bis 15:00", formatter: formatter
            )
            #expect(!widget.isAvailable)
            #expect(widget.differenceText == nil)
            #expect(widget.percentText == nil)
            PaceLocalization.$languageOverride.withValue(.german) {
                #expect(widget.headline == "Noch kein Vergleich verfügbar")
            }
        }
        // Gestern bis jetzt 0 Schritte: Unterschied ja, aber kein erfundener Prozentwert.
        let early = HomeDayComparisonWidget(
            todaySteps: 400, yesterdayHourly: [20: 3_000], yesterdayTotal: 3_000,
            currentHour: 9, fractionOfCurrentHour: 0, timeText: "bis 9:00", formatter: formatter
        )
        #expect(early.yesterdaySteps == 0)
        #expect(early.differenceText == "+400")
        #expect(early.percentText == nil)
        let behind = HomeDayComparisonWidget(
            todaySteps: 1_000, yesterdayHourly: [8: 2_000], yesterdayTotal: 2_000,
            currentHour: 10, fractionOfCurrentHour: 0, timeText: "bis 10:00", formatter: formatter
        )
        #expect(behind.direction == .behind)
        #expect(behind.differenceText == "−1.000")
    }

    // MARK: Aktivitätszeiten

    @Test func activityTimesBucketRealHourlyValues() {
        let hourly: [Int: Double] = [7: 640, 8: 1_210, 9: 380, 12: 1_450, 13: 520, 16: 980, 17: 2_102, 18: 1_150]
        let widget = HomeActivityTimesWidget(hourly: hourly, currentHour: 18, formatter: formatter)
        #expect(widget.buckets.map(\.steps) == [0, 2_230, 1_970, 3_082, 1_150])
        #expect(widget.totalSteps == 8_432)
        #expect(widget.peak?.id == "afternoon")
        #expect(widget.buckets.filter(\.isCurrent).map(\.id) == ["evening"])
        #expect(widget.hours.count == 24)
        #expect(widget.hours[17].level == 1)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(widget.peakText == "Am aktivsten: Nachmittag")
            #expect(widget.buckets[1].hours == "5–11 Uhr")
        }
    }

    @Test func activityTimesNeverInventADistribution() {
        let empty = HomeActivityTimesWidget(hourly: nil, currentHour: 10, formatter: formatter)
        #expect(empty.isEmpty)
        #expect(empty.peak == nil)
        #expect(empty.buckets.allSatisfy { $0.steps == 0 && !$0.isPeak })
    }

    // MARK: Persönliche Rekorde

    @Test func recordsComeFromTheStatisticsCalculation() {
        let today = Fixtures.day(2026, 10, 16)
        let calendar = Fixtures.activityCalendar
        var days: [DailyActivitySummary] = []
        for offset in -20...0 {
            let date = calendar.adding(offset, to: today)
            let steps = offset == -3 ? 15_200 : 6_000 + (offset + 20) * 100
            days.append(DailyActivitySummary(
                date: date, healthSteps: steps, competitionSteps: steps,
                walkingRunningDistanceMeters: Double(steps) * 0.7
            ))
        }
        let history = ActivityHistory(days: days, range: calendar.adding(-20, to: today)...today, updatedAt: Date())
        let bests = StatisticsReport.stepRecords(
            history: history, record: StepStreakRecord(days: 9, start: calendar.adding(-12, to: today), end: calendar.adding(-4, to: today)),
            currentStreak: 3, today: today, formatter: formatter, calendar: calendar
        )
        let widget = HomeRecordsWidget(bests: bests, selected: .bestDay)
        #expect(widget.primary?.value == "15.200 Schritte")
        #expect(widget.entries.map(\.kind).contains(.longestStreak))
        #expect(widget.entries.map(\.kind).contains(.currentStreak))
        #expect(widget.others.allSatisfy { $0.kind != .bestDay })
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(HomeRecordsWidget.periodText == "Letzte 12 Monate")
        }
        // Gewählter Rekord ohne Wert (z. B. noch keine Serie): kein erfundener Wert.
        let none = HomeRecordsWidget(bests: [], selected: .longestStreak)
        #expect(none.primary == nil)
        #expect(none.entries.isEmpty)
    }

    // MARK: Gruppenfortschritt

    @Test func groupProgressStates() {
        let group = SocialRepositoryStub.group(memberCount: 9, currentStreak: 3, reached: 2)
        #expect(HomeGroupProgressWidget(groupID: nil, groups: [group], isLoaded: true) == .unselected)
        #expect(HomeGroupProgressWidget(groupID: UUID(), groups: [group], isLoaded: true) == .missing)
        #expect(HomeGroupProgressWidget(groupID: UUID(), groups: [], isLoaded: false) == .loading)
        guard case .group(let shown, let progress) = HomeGroupProgressWidget(groupID: group.id, groups: [group], isLoaded: true) else {
            Issue.record("Gruppe erwartet")
            return
        }
        #expect(shown.id == group.id)
        #expect(progress.required == 3)
        #expect(progress.missing == 1)
    }

    // MARK: Speichern und Galerie

    @Test func newWidgetsAreStoredWithTheirOptions() throws {
        let groupID = UUID()
        let modules = [
            HomeModule(id: "cmp", kind: .dayComparison, size: .large, configuration: HomeWidgetConfiguration(details: [.yesterdayTotal])),
            HomeModule(id: "week", kind: .streakWeek, size: .small),
            HomeModule(id: "rec", kind: .records, size: .max, configuration: HomeWidgetConfiguration(record: .bestWeek)),
            HomeModule(id: "times", kind: .activityTimes, size: .medium),
            HomeModule(id: "grp", kind: .groupProgress, size: .large, configuration: HomeWidgetConfiguration(groupID: groupID)),
        ]
        let data = try JSONEncoder().encode(HomePreferences(modules: modules))
        let decoded = try JSONDecoder().decode(HomePreferences.self, from: data)
        #expect(decoded.modules == modules)
        #expect(decoded.modules[2].record == .bestWeek)
        #expect(decoded.modules[4].configuration.groupID == groupID)
        // Fremde Optionen werden nicht gespeichert (z. B. Kennzahl bei der Flammen-Woche).
        let sanitized = HomeModule(kind: .streakWeek, configuration: HomeWidgetConfiguration(metric: .distance, record: .bestDay))
        #expect(sanitized.configuration.metric == nil)
        #expect(sanitized.configuration.record == nil)
        // Unbekannter Rekord aus einer neueren Version: Standard „Bester Tag“.
        let json = #"{"version":3,"modules":[{"id":"r","kind":"records","size":"medium","config":{"record":"galaxy"}}]}"#
        let future = try JSONDecoder().decode(HomePreferences.self, from: Data(json.utf8))
        #expect(future.modules.first?.record == .bestDay)
    }

    @MainActor
    @Test func duplicatesFollowTheirContent() {
        let groupID = UUID()
        let settings = HomeSettings(store: InMemoryHomePreferencesStore())
        #expect(settings.add(HomeModule(kind: .records, configuration: HomeWidgetConfiguration(record: .bestDay))) != nil)
        #expect(settings.add(HomeModule(kind: .records, configuration: HomeWidgetConfiguration(record: .bestMonth))) != nil)
        #expect(settings.add(HomeModule(kind: .records, configuration: HomeWidgetConfiguration(record: .bestDay))) == nil)
        #expect(settings.add(HomeModule(kind: .groupProgress, configuration: HomeWidgetConfiguration(groupID: groupID))) != nil)
        #expect(settings.add(HomeModule(kind: .groupProgress, configuration: HomeWidgetConfiguration(groupID: groupID))) == nil)
        #expect(settings.add(.dayComparison) != nil)
        #expect(settings.add(.dayComparison) == nil)
    }

    @Test func gallerySectionsCoverEveryCategoryOnce() {
        let kinds = HomeGallerySection.allCases.flatMap(\.kinds)
        #expect(Set(kinds).count == kinds.count)
        #expect(Set(kinds) == Set(HomeModuleKind.allCases).subtracting([.stepsToday]))
        #expect(HomeModuleKind.dayComparison.gallerySection == .activity)
        #expect(HomeModuleKind.activityTimes.gallerySection == .activity)
        #expect(HomeModuleKind.streakWeek.gallerySection == .motivation)
        #expect(HomeModuleKind.records.gallerySection == .motivation)
        #expect(HomeModuleKind.groupProgress.gallerySection == .social)
        #expect(HomeModuleKind.stepsToday.gallerySection == .activity)
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(HomeGallerySection.allCases.map(\.title) == ["Активность", "Мотивация", "Общение"])
        }
    }

    @Test func everySizeHasSensibleDetails() {
        for kind in [HomeModuleKind.dayComparison, .streakWeek, .records, .activityTimes, .groupProgress] {
            #expect(kind.supportedSizes == HomeModuleSize.allCases)
            #expect(HomeModule(kind: kind, size: .small).shownDetails.isEmpty)
        }
        #expect(HomeModule(kind: .streakWeek, size: .max).shownDetails == [.streakCount, .record, .milestone])
        #expect(HomeModule(kind: .groupProgress, size: .large).shownDetails == [.groupHint, .groupGoal])
        #expect(HomeModule(kind: .dayComparison, size: .medium).shownDetails == [.comparisonBars])
    }
}
