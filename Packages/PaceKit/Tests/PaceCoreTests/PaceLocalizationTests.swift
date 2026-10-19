import Foundation
import PaceCore
import Testing

struct PaceLocalizationTests {
    @Test func textsFollowTheLanguageOfTheTask() {
        let german = PaceLocalization.$languageOverride.withValue(.german) {
            PaceLocalization.text(de: "Schritte", en: "Steps", ru: "Шаги")
        }
        let english = PaceLocalization.$languageOverride.withValue(.english) {
            PaceLocalization.text(de: "Schritte", en: "Steps", ru: "Шаги")
        }
        let russian = PaceLocalization.$languageOverride.withValue(.russian) {
            PaceLocalization.text(de: "Schritte", en: "Steps", ru: "Шаги")
        }
        #expect([german, english, russian] == ["Schritte", "Steps", "Шаги"])
    }

    @Test func russianHasThreePluralForms() {
        let forms = (one: "шаг", few: "шага", many: "шагов")
        let cases: [(Int, String)] = [
            (1, "шаг"), (2, "шага"), (4, "шага"), (5, "шагов"), (11, "шагов"), (12, "шагов"), (14, "шагов"),
            (21, "шаг"), (22, "шага"), (25, "шагов"), (101, "шаг"), (111, "шагов"), (0, "шагов"),
        ]
        PaceLocalization.$languageOverride.withValue(.russian) {
            for (count, expected) in cases {
                #expect(PaceLocalization.plural(count, de: ("", ""), en: ("", ""), ru: forms) == expected, "\(count)")
            }
        }
    }

    @Test func numbersUseTheFormatOfTheLanguage() {
        let formatted = AppLanguage.allCases.map { language in
            PaceLocalization.$languageOverride.withValue(language) { 8_432.paceFormatted }
        }
        #expect(formatted[0] == "8.432")
        #expect(formatted[1] == "8,432")
        // Russisch trennt Tausender mit (geschütztem) Leerzeichen.
        #expect(formatted[2].filter(\.isNumber) == "8432")
        #expect(formatted[2].count == 5)

        let steps = PaceLocalization.$languageOverride.withValue(.russian) { PaceLocalization.steps(2) }
        #expect(steps == "2 шага")
        let days = PaceLocalization.$languageOverride.withValue(.english) { PaceLocalization.days(1) }
        #expect(days == "1 day")
    }

    @Test func systemLanguageFallsBackToGerman() {
        #expect(AppLanguage.matching(preferredLanguages: ["fr-FR", "ru-RU"]) == .russian)
        #expect(AppLanguage.matching(preferredLanguages: ["en-GB"]) == .english)
        #expect(AppLanguage.matching(preferredLanguages: ["fr-FR", "es-ES"]) == .german)
        #expect(LanguagePreference.fixed(.english).resolved(preferredLanguages: ["de-DE"]) == .english)
    }

    @Test func preferencesSurviveUnknownValues() throws {
        let json = Data(#"{"appearance":"sepia","language":{"fixed":{"_0":"ru"}},"streakReminder":{"isEnabled":true,"hour":7,"minute":30}}"#.utf8)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: json)
        #expect(decoded.appearance == .automatic)
        #expect(decoded.language == .fixed(.russian))
        #expect(decoded.streakReminder == StreakReminderSettings(isEnabled: true, hour: 7, minute: 30))

        let roundTrip = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(decoded))
        #expect(roundTrip == decoded)
    }
}
