import ActivityFeature
import Foundation
import PaceCore
import PaceTestSupport
import Testing

/// Zahlen, Datumsangaben, Wochentage und Pluralformen je App-Sprache (Deutsch, Englisch, Russisch).
struct ActivityFormatterLanguageTests {
    private let calendar = Fixtures.activityCalendar
    private let day = Fixtures.day(2026, 10, 17)

    private func formatter(_ identifier: String) -> ActivityFormatter {
        ActivityFormatter(locale: Locale(identifier: identifier), calendar: calendar)
    }

    @Test func stepsFollowTheLanguage() {
        #expect(formatter("de_DE").steps(8_432) == "8.432")
        #expect(formatter("en_US").steps(8_432) == "8,432")
        let russian = formatter("ru_RU").steps(8_432)
        #expect(russian.hasPrefix("8") && russian.hasSuffix("432") && russian.count == 5)
        #expect(russian.unicodeScalars.contains { $0 == "\u{00A0}" || $0 == "\u{202F}" })
    }

    @Test func compactPercentMatchesTheReferences() {
        #expect(formatter("de_DE").compactPercent(0.8432) == "84%")
        #expect(formatter("en_US").compactPercent(0.8432) == "84%")
        #expect(formatter("ru_RU").compactPercent(0.8432) == "84\u{00A0}%")
        // 99,6 % sind noch nicht das ganze Ziel.
        #expect(formatter("de_DE").compactPercent(0.996) == "99%")
    }

    @Test func heartRateUnitsPerLanguage() {
        #expect(formatter("de_DE").beatsPerMinute(61.6) == ("62", "/min"))
        #expect(formatter("en_US").beatsPerMinute(98) == ("98", "bpm"))
        #expect(formatter("ru_RU").beatsPerMinute(98) == ("98", "уд/мин"))
    }

    @Test func datesAndWeekdaysPerLanguage() {
        #expect(formatter("de_DE").dayLong(day) == "Samstag, 17. Oktober")
        #expect(formatter("de_DE").dayLongWithYear(day) == "Samstag, 17. Oktober 2026")
        #expect(formatter("en_US").dayLong(day) == "Saturday, October 17")
        #expect(formatter("ru_RU").dayLong(day) == "Суббота, 17 октября")

        #expect(formatter("de_DE").monthYear(day) == "Oktober 2026")
        #expect(formatter("en_US").monthYear(day) == "October 2026")
        // Monatsname im Nominativ, großgeschrieben.
        #expect(formatter("ru_RU").monthYear(day) == "Октябрь 2026")

        #expect(formatter("de_DE").weekdayShort(day) == "Sa")
        #expect(formatter("en_US").weekdayShort(day) == "Sat")
        #expect(formatter("ru_RU").weekdayShort(day) == "Сб")
        #expect(formatter("de_DE").weekdayLetter(day) == "S")
        #expect(formatter("ru_RU").weekdayLetter(day) == "С")
    }

    @Test func weekStartFollowsTheLanguage() {
        #expect(formatter("de_DE").firstWeekday == 2)
        #expect(formatter("ru_RU").firstWeekday == 2)
        #expect(formatter("en_US").firstWeekday == 2)
    }

    @Test func russianPluralsForStepsAndDays() {
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(ActivityTexts.stepsWord(1) == "шаг")
            #expect(ActivityTexts.stepsWord(2) == "шага")
            #expect(ActivityTexts.stepsWord(5) == "шагов")
            #expect(ActivityTexts.stepsWord(11) == "шагов")
            #expect(ActivityTexts.stepsWord(21) == "шаг")
            #expect(ActivityTexts.stepsWord(8_432) == "шага")
            #expect(ActivityTexts.days(1) == "1 день")
            #expect(ActivityTexts.days(3) == "3 дня")
            #expect(ActivityTexts.days(12) == "12 дней")
            #expect(ActivityTexts.days(22) == "22 дня")
        }
    }

    @Test func stepsWithWordPerLanguage() {
        #expect(ActivityTexts.steps(1, formatter: formatter("de_DE")) == "1 Schritt")
        #expect(ActivityTexts.steps(8_432, formatter: formatter("de_DE")) == "8.432 Schritte")
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(ActivityTexts.steps(8_432, formatter: formatter("en_US")) == "8,432 steps")
            #expect(ActivityTexts.manualStepsNote == "Manually entered steps don't count for rankings.")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            let russian = formatter("ru_RU")
            #expect(ActivityTexts.steps(8_432, formatter: russian) == "\(russian.steps(8_432)) шага")
        }
    }

    @Test func statisticsTitlesAreLocalized() {
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(StatisticsPeriod.week.title == "Week")
            #expect(StatisticsMetric.distance.title == "Distance")
            #expect(StatisticsMetric.steps.unit(for: 1) == "step")
            #expect(StatisticsReport.unavailable == "not available")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(StatisticsPeriod.month.title == "Месяц")
            #expect(StatisticsMetric.steps.unit(for: 3) == "шага")
            #expect(StatisticsMetric.activeEnergy.unit == "ккал")
        }
    }

    @Test func streakSummaryFollowsTheLanguage() {
        let streak = StepStreak(
            current: 3,
            currentStart: Fixtures.day(2026, 10, 14),
            isTodayReached: false,
            longest: 12,
            longestRange: Fixtures.day(2026, 9, 1)...Fixtures.day(2026, 9, 12),
            reachesHistoryStart: false
        )
        let record = StepStreakRecord(days: 12, start: Fixtures.day(2026, 9, 1), end: Fixtures.day(2026, 9, 12))
        let recent = calendar.days(from: Fixtures.day(2026, 10, 11), through: day).map { ($0, StepStreakDayStatus.reached) }

        let german = StreakSummary(streak: streak, record: record, recentDays: recent, formatter: formatter("de_DE"))
        #expect(german.currentText == "3 Tage")
        #expect(german.recordText == "Rekord: 12 Tage")
        #expect(german.daysThroughYesterday == 3)
        #expect(german.lastWeek.map(\.letter) == ["M", "D", "M", "D", "F", "S", "S"])

        PaceLocalization.$languageOverride.withValue(.russian) {
            let russian = StreakSummary(streak: streak, record: record, recentDays: recent, formatter: formatter("ru_RU"))
            #expect(russian.currentText == "3 дня")
            #expect(russian.recordText == "Рекорд: 12 дней")
            #expect(russian.statusText == "Достигни цели сегодня, чтобы продолжить серию.")
            #expect(russian.lastWeek.map(\.letter) == ["П", "В", "С", "Ч", "П", "С", "В"])
        }
        PaceLocalization.$languageOverride.withValue(.english) {
            let english = StreakSummary(streak: streak, record: record, recentDays: recent, formatter: formatter("en_US"))
            #expect(english.currentText == "3 days")
            #expect(english.lastWeek.map(\.letter) == ["M", "T", "W", "T", "F", "S", "S"])
        }
    }

    @Test func streakThroughYesterdayExcludesTheRunningDay() {
        let reached = StepStreak(current: 4, currentStart: nil, isTodayReached: true, longest: 4, longestRange: nil, reachesHistoryStart: false)
        let open = StepStreak(current: 3, currentStart: nil, isTodayReached: false, longest: 3, longestRange: nil, reachesHistoryStart: false)
        #expect(reached.throughYesterday == 3)
        #expect(open.throughYesterday == 3)
        #expect(StepStreak.empty.throughYesterday == 0)
    }
}
